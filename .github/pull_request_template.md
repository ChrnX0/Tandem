## What changes

<!-- One or two sentences. The why matters more than the what. -->

## How you know it works

<!--
The project uses an explicit evidence hierarchy, and "done" requires at least E3:
  E1 static (I read the code)      E2 tested (the suite covers it)
  E3 exercised (I ran it and looked at the result)
  E4 in production (it worked on someone's machine)
Say which level you reached, and how.
-->

## Before marking as ready

- [ ] `bash tests/run.sh` passes
- [ ] `python3 build.py --check` passes
- [ ] If I added a test: I broke the code on purpose and confirmed the test fails
- [ ] If I added a command: it is in `uso()`, `man/tandem.1`, `README.md` and `LEIAME.md`
- [ ] No new error path ends in silence
- [ ] I do not write into a Wine prefix Tandem did not create
