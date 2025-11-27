# Secure deletion — what the app does and its limitations

This project attempts to implement file-level secure deletion (multiple overwrite passes) for deleted files stored in the app's private storage. However the behaviour of secure deletion is constrained by the underlying storage medium and OS.

Important points for the team and for users:

- Modern iOS devices use flash storage (NAND/SSD) and the operating system (APFS) may use wear-leveling and copy-on-write semantics. Overwriting a file's bytes on the filesystem does not guarantee that the physical flash locations are overwritten.

- The app's secure deletion implementation attempts to reduce data recoverability by:
  - Overwriting the file with cryptographically random data, complemented random data, and another random pass before removing the file.
  - Limiting overwrite sizes to a configurable maximum (e.g. 100MB) to keep operations performant and avoid excessive flash wear.

- This is a defense-in-depth measure — it may hinder casual data recovery but is not a substitute for full-disk hardware-level or secure-erase solutions.

- For highly-sensitive use cases where regulatory or threat-model constraints require guaranteed non-recoverability, a mechanical destruction or secure erasure at the filesystem/device level is required.

Developer notes:

- Keep users informed in the UI if secure deletion is enabled and what it does. Add an explicit note in Preferences / Privacy explaining the limitation.
- Avoid showcasing secure deletion as absolute 'perfect' deletion.
- Tests and docs should ensure the secure deletion flow handles errors gracefully and falls back to normal deletion.
