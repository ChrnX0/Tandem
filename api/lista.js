// Tandem - the community list intake.
//
// One shop's Tandem learns that a program needed vcrun2022, and every other
// Tandem should receive that lesson. This is the receiving end of that, and it
// is the only part of the project that faces the open internet.
//
// WHY IT EXISTS HERE, in the same repository as the client that posts to it:
// the code that receives a shop's data has to be as readable as the code that
// sends it. The alternative - a service somewhere with its own repository - is
// how "we only collect anonymous data" becomes a claim nobody can check.
//
// WHAT IT MAY NOT DO, and this is the whole design:
//
//   It does not trust the sender. The client runs a privacy sieve before it
//   queues a line, but anyone can craft a POST by hand, so every rule is
//   applied AGAIN here. A client-side check is a courtesy to the owner, never
//   a guarantee to anybody else.
//
//   It does not keep the address it was called from. Not in a log line, not in
//   a hash, not in a "salted" form. See the note on counting below - the honest
//   consequence is that this counts REPORTS and not MACHINES, and the format
//   documentation says so out loud rather than quietly meaning something else.
//
//   It does not let the sender assert how many machines agree. The count is the
//   list's to compute; a record arriving with "400" in that field is refused,
//   because a number anybody can type is a number that means nothing.
import { put } from "@vercel/blob";

// A record is eight TAB-separated fields and about ninety bytes. The cap is
// generous by a factor of five and still small enough that a hostile body
// cannot become a memory problem.
const LIMITE_BYTES = 512;

// The shape of each field, from docs/LIST-FORMAT.md. Checked against what the
// client actually produces rather than against what the document says it does:
// t_memoria_id cuts sha256 to 32 characters, so an identity is 32 hex digits
// and not 64. A validator written from the prose alone would have refused every
// real record, which is the sort of thing that is only found by reading the
// code that makes them.
const CAMPOS = [
  { nome: "identity",   ok: (v) => /^[0-9a-f]{32}$/.test(v) },
  { nome: "arch",       ok: (v) => /^(32|64|arm64|-)$/.test(v) },
  { nome: "verbs",      ok: (v) => v === "-" || /^[a-z0-9_]+(,[a-z0-9_]+)*$/.test(v) },
  { nome: "failed",     ok: (v) => v === "-" || /^[a-z0-9_]+(,[a-z0-9_]+)*$/.test(v) },
  { nome: "confidence", ok: (v) => /^(confirmado|so-abriu|reprovado)$/.test(v) },
  // Not "any number": exactly one. One POST is one report, and the sender does
  // not get to speak for a hundred shops it has never met.
  { nome: "machines",   ok: (v) => v === "1" },
  { nome: "seen",       ok: (v) => /^\d{4}-(0[1-9]|1[0-2])$/.test(v) },
  // Free text is the field most likely to carry something personal by accident
  // - a program name, a shop name, a path someone pasted. The client always
  // sends "-" today, so accepting only "-" costs nothing and closes the one
  // field a sieve has to guess about. Widen it the day there is a reason, with
  // the rules from LIST-FORMAT.md applied here first.
  { nome: "note",       ok: (v) => v === "-" },
];

// A verb name arriving from outside is a name, never a command line. This is
// the same rule the client applies at the point of use, and it is repeated here
// for the same reason everything else is: the client's copy protects the owner
// who runs it, not the list.
const VERBO_MAX = 40;

// Vercel's Node runtime gives status/send/json/setHeader and NOT Express's
// res.type(). Every response path in this file went through one call to it, so
// the function answered 500 to everything - including the GET that is supposed
// to refuse before touching anything. Confirmed from the runtime stack trace
// rather than guessed, and it is the same shape as the defects this project
// keeps finding: not a wrong rule, a rule that could never run.
function texto(res, codigo) {
  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  return res.status(codigo);
}

function recusa(res, motivo) {
  // The reason goes back in plain text because the caller is a shell script
  // reading an HTTP code, and because a refusal nobody can read is the silent
  // failure this project exists to kill. It names WHAT was wrong and never
  // echoes the body back - an error page that quotes its input is a way to make
  // somebody else's data appear in somebody else's log.
  texto(res, 400).send(motivo + "\n");
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    // A GET here is somebody looking, not somebody contributing. Answer with
    // what this is, so a person who finds the URL can go read the code.
    return texto(res, 405).send(
      "Tandem community list intake. POST one TAB-separated record.\n" +
        "Format: https://github.com/ChrnX0/Tandem/blob/main/docs/LIST-FORMAT.md\n"
    );
  }

  let corpo = typeof req.body === "string" ? req.body : "";
  if (Buffer.byteLength(corpo, "utf8") > LIMITE_BYTES) {
    return recusa(res, "record too long");
  }

  // One line. A body with a second line is either a mistake or an attempt to
  // smuggle a row past a per-line check, and neither is worth accepting.
  corpo = corpo.replace(/\n$/, "");
  if (corpo.includes("\n") || corpo.includes("\r")) {
    return recusa(res, "one record per request");
  }

  const campos = corpo.split("\t");
  if (campos.length !== CAMPOS.length) {
    return recusa(res, `expected ${CAMPOS.length} fields, got ${campos.length}`);
  }
  for (let i = 0; i < CAMPOS.length; i++) {
    if (!CAMPOS[i].ok(campos[i])) {
      return recusa(res, `field ${i + 1} (${CAMPOS[i].nome}) is not in the format`);
    }
  }

  const [identity, , verbs, failed, confidence] = campos;

  // A record that carries no lesson is noise in everybody else's list. The
  // client refuses to build one; this refuses to store one.
  if (verbs === "-" && failed === "-" && confidence !== "reprovado") {
    return recusa(res, "record carries no lesson");
  }
  for (const v of (verbs + "," + failed).split(",")) {
    if (v !== "-" && v.length > VERBO_MAX) {
      return recusa(res, "verb name too long");
    }
  }

  // The month cannot be in the future and cannot predate the format. Both ends
  // matter: a record dated 2999-12 would sort above every honest row for ever.
  const agora = new Date();
  const mesAgora = `${agora.getUTCFullYear()}-${String(agora.getUTCMonth() + 1).padStart(2, "0")}`;
  if (campos[6] > mesAgora || campos[6] < "2026-01") {
    return recusa(res, "the date is not a month this list can have seen");
  }

  // ------------------------------------------------------------------
  // Storage. One blob per record, under the identity it is about, so the job
  // that rebuilds lista.tsv can walk them by program.
  //
  // ON COUNTING, and this is the part worth reading before changing anything:
  // the published format has a "machines" field, and counting machines
  // honestly needs a way to tell two shops apart - which is exactly what this
  // endpoint refuses to keep. Every scheme that gets a real machine count
  // (hash the address, salt it, rotate the salt) stores something derived from
  // the address, and a hash of an IPv4 address is an IPv4 address to anybody
  // willing to try four billion of them.
  //
  // So this counts REPORTS. A shop that sends the same lesson twice counts
  // twice, and docs/LIST-FORMAT.md says that in those words. That is a smaller
  // claim than the field name suggests, and the right response is to shrink the
  // claim rather than to keep the number and quietly mean something else.
  const chave = `entrada/${identity}/${crypto.randomUUID()}.tsv`;
  try {
    await put(chave, corpo + "\n", {
      access: "public",
      contentType: "text/plain; charset=utf-8",
      addRandomSuffix: false,
    });
  } catch (e) {
    // The store is not configured, or it is full, or it is down. Whichever it
    // is, the client must NOT read this as a delivery: it keeps the line in its
    // queue and tries again later, and it only does that if the answer is not
    // 2xx. Since 4.4 the client reads the status code explicitly instead of
    // trusting curl's exit status, which used to count a redirect as an
    // arrival and then delete the only copy of the lesson.
    console.error("store refused:", e && e.message);
    return texto(res, 503).send("store unavailable\n");
  }

  return res.status(204).end();
}
