# Shared terminal colors for install / mlx-serve / loop scripts.
# Respects NO_COLOR and non-TTY output (piped logs stay plain).

if [[ -n "${LLM_COLORS_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
LLM_COLORS_LOADED=1

_llm_use_color() {
  [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 || -t 2 ]]
}

if _llm_use_color; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_CYAN=$'\033[36m'
  C_BLUE=$'\033[34m'
  C_MAGENTA=$'\033[35m'
else
  C_RESET= C_BOLD= C_DIM= C_GREEN= C_YELLOW= C_RED= C_CYAN= C_BLUE= C_MAGENTA=
fi

export C_RESET C_BOLD C_DIM C_GREEN C_YELLOW C_RED C_CYAN C_BLUE C_MAGENTA
export LLM_C_RESET="$C_RESET" LLM_C_BOLD="$C_BOLD" LLM_C_DIM="$C_DIM"
export LLM_C_GREEN="$C_GREEN" LLM_C_YELLOW="$C_YELLOW" LLM_C_RED="$C_RED"
export LLM_C_CYAN="$C_CYAN" LLM_C_BLUE="$C_BLUE" LLM_C_MAGENTA="$C_MAGENTA"

log()  { printf '%b\n' "${C_CYAN}${C_BOLD}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
warn() { printf '%b\n' "${C_YELLOW}${C_BOLD}WARNING:${C_RESET} $*" >&2; }
die()  { printf '%b\n' "${C_RED}${C_BOLD}ERROR:${C_RESET} $*" >&2; exit 1; }

ok()        { printf '%b\n' "${C_GREEN}${C_BOLD}OK${C_RESET}   $*"; }
fail()      { printf '%b\n' "${C_RED}${C_BOLD}FAIL${C_RESET} $*" >&2; }
warn_note() { printf '%b\n' "${C_YELLOW}${C_BOLD}WARN${C_RESET} $*" >&2; }
fix_hint()  { printf '%b\n' "${C_DIM}      Fix: $*${C_RESET}" >&2; }

section() {
  printf '%b\n' "${C_BLUE}${C_BOLD}--- $* ---${C_RESET}"
}

banner() {
  local title="$1"
  printf '%b\n' "${C_CYAN}==============================================${C_RESET}"
  printf '%b\n' "${C_CYAN}${C_BOLD} ${title}${C_RESET}"
  printf '%b\n' "${C_CYAN}==============================================${C_RESET}"
}

success_msg() { printf '%b\n' "${C_GREEN}${C_BOLD}$*${C_RESET}"; }
error_msg()   { printf '%b\n' "${C_RED}${C_BOLD}$*${C_RESET}" >&2; }
dim_line()    { printf '%b\n' "${C_DIM}$*${C_RESET}"; }

label_value() {
  local label="$1" value="$2"
  printf '  %b%s:%b  %s\n' "$C_DIM" "$label" "$C_RESET" "$value"
}

report_version_change() {
  local name="$1" before="$2" after="$3"
  if [[ "$before" == "$after" ]]; then
    printf '  %s:  %s %b(unchanged)%b\n' "$name" "$after" "$C_DIM" "$C_RESET"
  else
    printf '  %s:  %s %b→%b %s\n' "$name" "$before" "$C_YELLOW" "$C_RESET" "$after"
  fi
}
