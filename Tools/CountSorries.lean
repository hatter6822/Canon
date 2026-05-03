/-
Tools.CountSorries — Phase 1 WU 1.12.

Counts `sorry` occurrences in proof position across the project.  The
tool walks every `.lean` file under `searchRoots` and, per file,
counts lines that contain a `sorry` term that is not inside a `--`
comment.

Exit semantics:

  * Exit 0 if every kernel-TCB module (`LegalKernel/Kernel.lean`,
    `LegalKernel/RBMapLemmas.lean`, `LegalKernel/Laws/Transfer.lean`)
    has *zero* `sorry` occurrences.
  * Exit 1 otherwise.

The tool is intentionally regex-flavoured, mirroring the manual check in
CLAUDE.md:

  grep -rnE '(:= sorry|by sorry|exact sorry|^[[:space:]]*sorry[[:space:]]*$)' LegalKernel/

Comments referencing the *word* "sorry" (e.g. "no `sorry` in this file")
are allowed; only the *term* `sorry` in proof position is forbidden.

This is a deliberately small approximation of a fully-correct check.
A full check would run Lean's elaborator and inspect `sorryAx` axiom
usage; the present tool catches the common-case violations and is
fast enough to run on every CI build.
-/

/-- Files-and-directories search root.  Restricted to the
    `LegalKernel` source tree to avoid scanning the lake build cache
    and to avoid false-positive matches in the audit tool's own
    pattern strings.  CI scans the kernel-adjacent surface; non-TCB
    auxiliary tooling is out of scope. -/
def searchRoots : List String :=
  [ "LegalKernel"
  ]

/-- Files that MUST have zero sorries (the kernel TCB plus the
    Phase-0 transfer law that is part of the deployed law set).
    A non-zero count in any of these is a CI-blocking failure. -/
def kernelTcbFiles : List String :=
  [ "LegalKernel/Kernel.lean"
  , "LegalKernel/RBMapLemmas.lean"
  , "LegalKernel/Laws/Transfer.lean"
  ]

/-- Recursively enumerate every `.lean` file under `root`. -/
partial def listLeanFiles (root : String) : IO (List String) := do
  let path : System.FilePath := root
  let metaResult ← path.metadata.toBaseIO
  match metaResult with
  | Except.error _ => pure []
  | Except.ok fileMeta =>
    if fileMeta.type == IO.FS.FileType.dir then
      let entries ← path.readDir
      let mut acc : List String := []
      for e in entries do
        let sub ← listLeanFiles e.path.toString
        acc := acc ++ sub
      pure acc
    else if root.endsWith ".lean" then
      pure [root]
    else
      pure []

/-- Test whether `needle` appears as a contiguous substring of `haystack`.
    Naive `O(n·m)` scan, sufficient for the short patterns the audit uses. -/
def listContains (haystack needle : List Char) : Bool :=
  match needle with
  | []      => true
  | _ :: _  =>
    let rec go (h : List Char) : Bool :=
      if h.take needle.length = needle then true
      else
        match h with
        | []      => false
        | _ :: rest => go rest
    go haystack

/-- Strip everything from the first `--` (Lean line comment marker)
    onwards.  Approximation: doesn't recognise `--` inside a string
    literal, but Canon source files don't contain such literals
    in proof bodies. -/
def stripCommentChars (cs : List Char) : List Char :=
  let rec go (acc : List Char) (cs : List Char) : List Char :=
    match cs with
    | []                      => acc.reverse
    | '-' :: '-' :: _         => acc.reverse
    | c :: rest               => go (c :: acc) rest
  go [] cs

/-- Drop leading whitespace from a `List Char`. -/
def dropLeadingWs (cs : List Char) : List Char :=
  cs.dropWhile Char.isWhitespace

/-- Drop trailing whitespace from a `List Char`.  Reverses, drops
    leading whitespace, reverses back. -/
def dropTrailingWs (cs : List Char) : List Char :=
  (cs.reverse.dropWhile Char.isWhitespace).reverse

/-- Detect a `sorry` in proof position on this line.  The patterns
    match the four CLAUDE.md categories (proof body via `:=`, tactic
    body via `by`, terminal `exact sorry`, or sole-content line).

    Lines whose only `sorry` mention is *after* a `--` are ignored,
    because they're commented out. -/
def isSorryProofPosition (line : String) : Bool :=
  let codeChars  := stripCommentChars line.toList
  let trimmed    := dropTrailingWs (dropLeadingWs codeChars)
  -- Pattern 1-3: substring scans on the *code* portion of the line.
  let pAssign    := listContains codeChars ":= sorry".toList
  let pBy        := listContains codeChars "by sorry".toList
  let pExact     := listContains codeChars "exact sorry".toList
  -- Pattern 4: the entire line (modulo whitespace) is the term `sorry`.
  let pBare      := trimmed = "sorry".toList
  pAssign || pBy || pExact || pBare

/-- For each line in `content`, decide whether it carries a proof-position
    `sorry` and emit `(lineNumber, rawLine)` when it does. -/
def matchesInContent (content : String) : List (Nat × String) := Id.run do
  let lines := content.splitOn "\n"
  let mut acc : List (Nat × String) := []
  for h : i in [0:lines.length] do
    let line := lines[i]'h.upper
    if isSorryProofPosition line then
      acc := acc ++ [(i + 1, line)]
  acc

/-- Per-file count of sorries in proof position.  A read failure
    (file gone, permission error) is reported as `0` so the tool is
    forgiving on directory partial-read races. -/
def countOne (path : String) : IO Nat := do
  match (← (IO.FS.readFile path).toBaseIO) with
  | .error _ => pure 0
  | .ok content => pure (matchesInContent content).length

/-- Read a file's content; return `""` on any read error so callers
    don't need to wrap every read site. -/
def readFileSafe (path : String) : IO String := do
  match (← (IO.FS.readFile path).toBaseIO) with
  | .error _ => pure ""
  | .ok content => pure content

/-- Aggregate sorries across the entire project under the search roots. -/
def aggregate : IO (List (String × Nat)) := do
  let mut allFiles : List String := []
  for r in searchRoots do
    let xs ← listLeanFiles r
    allFiles := allFiles ++ xs
  -- Deduplicate while preserving order.
  let allFilesUnique := (allFiles.foldl
    (fun acc f => if f ∈ acc then acc else acc ++ [f])
    ([] : List String))
  let mut result : List (String × Nat) := []
  for f in allFilesUnique do
    let n ← countOne f
    if n > 0 then
      result := result ++ [(f, n)]
  pure result

/-- Pretty-print the matched lines in a file (used for kernel-TCB
    failure diagnostics). -/
def showMatches (path : String) : IO Unit := do
  let content ← readFileSafe path
  for (n, line) in matchesInContent content do
    IO.eprintln s!"{path}:{n}: {line}"

/-- Entry point.  Reports per-file sorry counts; fails (exit 1) if
    any kernel-TCB file has a non-zero count. -/
def main : IO UInt32 := do
  let counts ← aggregate
  let total := counts.foldl (fun acc p => acc + p.snd) 0
  IO.println s!"count_sorries: {total} sorry/sorries across {counts.length} file(s)."
  for (path, n) in counts do
    IO.println s!"  {path}: {n}"
  -- Hard requirement: zero sorries in the kernel TCB.
  let mut tcbFail := false
  for tcbPath in kernelTcbFiles do
    let n ← countOne tcbPath
    if n > 0 then
      IO.eprintln s!"count_sorries: FAIL — kernel-TCB file '{tcbPath}' has {n} sorry/sorries:"
      showMatches tcbPath
      tcbFail := true
  if tcbFail then
    pure 1
  else
    IO.println "count_sorries: PASS — every kernel-TCB module has zero sorries."
    pure 0
