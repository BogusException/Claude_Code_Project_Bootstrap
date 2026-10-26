#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
err() { printf '%s\n' "$*" >&2; }
source "$ROOT/lib/input.sh"
count=0
accept() {
    if ! "$@" >/dev/null 2>&1; then
        printf 'FAIL: expected acceptance: %q\n' "$*" >&2; exit 1
    fi
    count=$((count + 1))
}
reject() {
    if "$@" >/dev/null 2>&1; then
        printf 'FAIL: expected rejection: %q\n' "$*" >&2; exit 1
    fi
    count=$((count + 1))
}
printf -v name64 'a%063d' 0
for name in a my_tool agent2024 "$name64"; do accept validate_name "$name"; done
for name in "" MyTool UPPER _bad 2bad my-tool "my tool" " bad" "bad " "bad.name" "bad/name" "../escape" 'bad\name' 'a;touch marker' 'a$(touch marker)' $'a\nb' $'a\rb' $'a\tb' $'a\033b' "café" "ａｂｃ" "${name64}a"; do
    reject validate_name "$name"
done
for name in and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield; do
    reject validate_name "$name"
done
printf -v huge '%010000d' 0
reject validate_name "a$huge"
accept validate_cli_args
for arg in --help -h --usage --test my_tool; do accept validate_cli_args "$arg"; done
reject validate_cli_args ""
reject validate_cli_args --unknown
reject validate_cli_args one two
reject validate_cli_args --help extra
reject validate_cli_args --test extra

choose() {
    local actual
    read_choice actual "" "$1" "$2" || return
    [[ "$actual" == "$3" ]]
}
for answer in y Y n N; do accept choose y yYnN "${answer,,}" <<< "$answer"; done
accept choose y yYnN y <<< ""
for answer in 1 2 3 4 5 6 7 8; do accept choose 2 12345678 "$answer" <<< "$answer"; done
for answer in 1 2 3 4; do accept choose 2 1234 "$answer" <<< "$answer"; done
accept choose 2 12345678 2 <<< ""
for bad in x yes no yy nn " y" "y " " " 0 9 -1 12 $'y\r' $'y\t' $'\033'; do
    accept choose y yYnN n <<< "$bad"$'\nn'
    reject choose y yYnN y <<< "$bad"
done
for bad in 0 9 12 01 2.0 -1 A $'2\t' $'2\r' " 2"; do
    accept choose 2 12345678 1 <<< "$bad"$'\n1'
    reject choose 2 12345678 2 <<< "$bad"
done
for bad in 0 5 8 44 02 a; do
    accept choose 2 1234 3 <<< "$bad"$'\n3'
    reject choose 2 1234 2 <<< "$bad"
done
accept choose y yYnN n <<< "$huge"$'\nn'
reject choose y yYnN y < /dev/null
reject choose 2 12345678 2 < /dev/null
reject choose 2 1234 2 < /dev/null
reject choose y yYnN y < <(printf y)

scratch="$(mktemp -d /tmp/mkproj-input-test.XXXXXXXX)"
trap 'rm -rf -- "$scratch"' EXIT
printf -v path2048 '/%02047d' 0
accept validate_project_path "$path2048"
reject validate_project_path "${path2048}a"
reject validate_project_path "$scratch/"$'bad\nparent'
reject validate_project_path "$scratch/"$'bad\033parent'
touch "$scratch/existing_file"
ln -s "$scratch/absent" "$scratch/broken_link"
reject validate_project_path "$scratch/existing_file"
reject validate_project_path "$scratch/broken_link"
mkdir -p "$scratch/bin" "$scratch/parent's space" "$scratch/work"
accept validate_project_path "$scratch/parent's space/project"
for command in screen git python3 jq claude; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "$MKPROJ_TEST_CALLS"\nexit 93\n' "$command" > "$scratch/bin/$command"
    chmod +x "$scratch/bin/$command"
done
export MKPROJ_TEST_CALLS="$scratch/calls"
for arg in "" MyTool "../escape" 'a;touch marker' "${name64}a" --unknown; do
    if (cd "$scratch/work" && PATH="$scratch/bin:$PATH" bash "$ROOT/bootstrap.sh" "$arg") >/dev/null 2>&1; then
        err "FAIL: invalid CLI accepted"; exit 1
    fi
    [[ ! -e "$scratch/calls" ]] || { err "FAIL: invalid CLI reached external commands"; exit 1; }
    [[ -z "$(ls -A "$scratch/work")" ]] || { err "FAIL: invalid CLI changed filesystem"; exit 1; }
    count=$((count + 1))
done
for invocation in extra_args help_extra test_extra; do
    case "$invocation" in
        extra_args) args=(valid_name extra) ;;
        help_extra) args=(--help extra) ;;
        test_extra) args=(--test extra) ;;
    esac
    if (cd "$scratch/work" && PATH="$scratch/bin:$PATH" bash "$ROOT/bootstrap.sh" "${args[@]}") >/dev/null 2>&1; then
        err "FAIL: extra CLI arguments accepted"; exit 1
    fi
    [[ ! -e "$scratch/calls" && -z "$(ls -A "$scratch/work")" ]] || exit 1
    count=$((count + 1))
done
for input in n N garbage; do
    if (cd "$scratch/work" && STY=isolated PATH="$scratch/bin:$PATH" bash "$ROOT/bootstrap.sh" valid_name <<< "$input") >/dev/null 2>&1; then
        err "FAIL: cancellation/EOF continued"; exit 1
    fi
    [[ ! -e "$scratch/calls" && ! -e "$scratch/work/valid_name" ]] || exit 1
    count=$((count + 1))
done
if (cd "$scratch/work" && STY=isolated PATH="$scratch/bin:$PATH" bash "$ROOT/bootstrap.sh" valid_name < /dev/null) >/dev/null 2>&1; then
    err "FAIL: EOF continued"; exit 1
fi
[[ ! -e "$scratch/calls" && ! -e "$scratch/work/valid_name" ]] || exit 1
count=$((count + 1))
# Valid CLI names must actually reach the first confirmation, not fail validation.
for valid in a my_tool "$name64"; do
    output="$(cd "$scratch/work" && STY=isolated PATH="$scratch/bin:$PATH" bash "$ROOT/bootstrap.sh" "$valid" <<< n 2>&1)" && exit 1
    [[ "$output" == *"Aborted."* ]] || { err "FAIL: valid CLI name rejected before confirmation"; exit 1; }
    [[ ! -e "$scratch/calls" && ! -e "$scratch/work/$valid" ]] || exit 1
    count=$((count + 1))
done
# Every help spelling exits cleanly with no setup side effects.
for option in --help -h --usage; do
    (cd "$scratch/work" && PATH="$scratch/bin:$PATH" bash "$ROOT/bootstrap.sh" "$option") >/dev/null
    [[ ! -e "$scratch/calls" ]] || exit 1
    count=$((count + 1))
done
mkdir "$scratch/BadName"
if (cd "$scratch/BadName" && PATH="$scratch/bin:$PATH" bash "$ROOT/bootstrap.sh") >/dev/null 2>&1; then exit 1; fi
[[ ! -e "$scratch/calls" ]] || exit 1
count=$((count + 1))
printf 'PASS: %s input, boundary, EOF, and no-side-effect checks\n' "$count"
