// Tandem - what the intake has accepted so far, in the published format.
//
// The job that rebuilds lista/lista.tsv reads THIS, not the store directly, and
// that is the whole reason it exists: listing a Vercel Blob store needs the
// read-write token, so a GitHub Action doing it directly would need that token
// in the repository's secrets. Reading a URL needs nothing. One less credential
// created by hand, which was the requirement.
//
// It is safe to serve openly because every record here already passed the
// intake's validation, and the intake accepts nothing that is not destined for
// a public file in a public repository anyway. There is nothing here that is
// not already on its way to being published.
import { list } from "@vercel/blob";

export default async function handler(req, res) {
  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  if (req.method !== "GET") {
    return res.status(405).send("GET only\n");
  }

  const linhas = [];
  let cursor;
  try {
    // Paginated on purpose. A store with more records than one page is the
    // situation this project is trying to reach, so the code that reads it
    // must not be written as though it will never happen.
    do {
      const pagina = await list({ prefix: "entrada/", cursor, limit: 1000 });
      for (const b of pagina.blobs) {
        const r = await fetch(b.url);
        if (!r.ok) continue;
        const linha = (await r.text()).trim();
        if (linha) linhas.push(linha);
      }
      cursor = pagina.hasMore ? pagina.cursor : undefined;
    } while (cursor);
  } catch (e) {
    console.error("list refused:", e && e.message);
    return res.status(503).send("store unavailable\n");
  }

  // Sorted so the output is stable: the job that rebuilds the list should see a
  // diff only when a record actually changed, not because a store returned its
  // pages in a different order.
  linhas.sort();
  res.setHeader("Cache-Control", "public, max-age=300");
  return res
    .status(200)
    .send(`# TANDEM-ENTRADA 1 - ${linhas.length} record(s)\n${linhas.join("\n")}\n`);
}
