//! WO13 validation harness: compile grammar/isc.parg with parsanol-rs
//! and parse .isc corpus files with it.
//!
//! Usage:
//!   isc-parg-check <grammar.parg> <file-or-dir>... [--expect-reject]
//!
//! Each .isc file must parse to completion (the grammar pins EOF with
//! `!utf`). On failure the failure wire (offset, line, column, expected
//! set) is printed. Exit status: 0 all pass, 1 any failure.
//!
//! `--expect-reject` flips the verdict: every listed file must FAIL to
//! parse (negative corpus).

use parsanol::parg::frontend::compile::{compile_entry_mode, Tables};
use parsanol::parg::frontend::parser::parse_grammar_with_mode;
use parsanol::{AstArena, PortableParser};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let expect_reject = match args.iter().position(|a| a == "--expect-reject") {
        Some(i) => {
            args.remove(i);
            true
        }
        None => false,
    };
    if args.len() < 2 {
        eprintln!("usage: isc-parg-check <grammar.parg> <file-or-dir>... [--expect-reject]");
        return ExitCode::from(2);
    }
    let parg_path = args.remove(0);

    let source = match std::fs::read_to_string(&parg_path) {
        Ok(s) => s,
        Err(err) => {
            eprintln!("{}: unreadable: {err}", parg_path);
            return ExitCode::from(2);
        }
    };
    let (parsed, mode) = match parse_grammar_with_mode(&source) {
        Ok(pair) => pair,
        Err(err) => {
            eprintln!("{}: parg parse failed: {err}", parg_path);
            return ExitCode::from(2);
        }
    };
    let grammar = match compile_entry_mode(
        &parsed.document,
        "isc",
        &Tables::new(),
        &parsed.atomic_rules,
        mode.as_deref(),
    ) {
        Ok(g) => g,
        Err(err) => {
            eprintln!("{}: parg compile failed: {err}", parg_path);
            return ExitCode::from(2);
        }
    };
    println!(
        "compiled {} (edition {:?}) — {} rules",
        parg_path,
        mode.as_deref().unwrap_or("1"),
        parsed.document.rules.len()
    );

    let mut files: Vec<PathBuf> = Vec::new();
    for arg in &args {
        let path = Path::new(arg);
        if path.is_dir() {
            let mut dir_files: Vec<PathBuf> = walk_isc(path);
            dir_files.sort();
            files.extend(dir_files);
        } else {
            files.push(path.to_path_buf());
        }
    }

    let mut passed = 0usize;
    let mut failed = 0usize;
    for file in &files {
        let input = match std::fs::read_to_string(file) {
            Ok(s) => s,
            Err(err) => {
                eprintln!("FAIL {} (unreadable: {err})", file.display());
                failed += 1;
                continue;
            }
        };
        let mut arena = AstArena::for_input(input.len().max(1 << 16));
        let mut parser = PortableParser::new(&grammar, &input, &mut arena);
        let outcome = parser.parse();
        let ok = outcome.is_ok();
        let wanted = if expect_reject { !ok } else { ok };
        if wanted {
            passed += 1;
            if expect_reject {
                println!("OK   {} (rejected as expected)", file.display());
            }
        } else if ok {
            println!("FAIL {} (parsed, expected rejection)", file.display());
            failed += 1;
        } else {
            let err = outcome.unwrap_err();
            let msg = match (err.is_abort(), parser.failure_wire()) {
                (false, Some((offset, expected))) => {
                    let (line, column) = line_column(&input, offset);
                    format!(
                        "offset {offset} line {line} col {column}, expected one of: {expected:?}"
                    )
                }
                _ => format!("{err:?}"),
            };
            println!("FAIL {} ({msg})", file.display());
            failed += 1;
        }
    }

    println!(
        "{passed}/{}/{} files {}",
        passed + failed,
        files.len(),
        if expect_reject { "rejected" } else { "parsed" }
    );
    if failed == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn walk_isc(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let entries = match std::fs::read_dir(&dir) {
            Ok(entries) => entries,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().and_then(|e| e.to_str()) == Some("isc") {
                out.push(path);
            }
        }
    }
    out
}

fn line_column(input: &str, offset: usize) -> (usize, usize) {
    let mut line = 1usize;
    let mut column = 1usize;
    for (index, ch) in input.char_indices() {
        if index >= offset {
            break;
        }
        if ch == '\n' {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    (line, column)
}
