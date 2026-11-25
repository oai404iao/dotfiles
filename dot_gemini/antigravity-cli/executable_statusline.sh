#!/usr/bin/env bash
input=$(cat)

out=$(jq -er '
  def fixed($digits):
    pow(10; $digits) as $scale
    | (. * $scale | round) as $n
    | "\($n / $scale | floor)." + (("0" * $digits) + ($n % $scale | tostring))[-$digits:];
  def short_decimal: fixed(1) | sub("\\.0$"; "");
  def compact($units):
    if . >= 999.95 and ($units | length) > 1 then
      . / 1000 | compact($units[1:])
    else short_decimal + $units[0]
    end;
  def tokens: compact(["", "k", "M", "B"]);
  def cache_hit:
    .cache_read_input_tokens as $read
    | if ($read | type) == "number" and (.input_tokens | type) == "number" then
        # agy reports uncached input, cache writes, and cache reads separately.
        (.input_tokens + (.cache_creation_input_tokens // 0) + $read) as $total
        | if $total > 0 then " CH\(100 * $read / $total | fixed(1))%" else "" end
      else "" end;

  .context_window as $ctx
  | "↑\($ctx.total_input_tokens // 0 | tokens) ↓\($ctx.total_output_tokens // 0 | tokens)"
    + ($ctx.current_usage | cache_hit)
    + (if (.cost.total_usd | type) == "number" then " $\(.cost.total_usd | fixed(3))" else "" end)
    + " \($ctx.used_percentage // 0 | short_decimal)%/\($ctx.context_window_size // 0 | if . > 0 then tokens else "?" end)"
' <<< "$input") || exit 1
branch=$(jq -r 'select((.vcs.type // "git") == "git") | .vcs.branch // empty' <<< "$input")
if [[ -z $branch ]]; then
  cwd=$(jq -r '.cwd // empty' <<< "$input")
  if [[ -n $cwd ]]; then
    branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null) || branch=''
  fi
fi

if [[ -n $branch ]]; then
  out="$out | git:$branch"
fi

width=$(jq -r '.terminal_width // empty' <<< "$input")
if [[ $width =~ ^[1-9][0-9]*$ ]]; then
  columns=$(printf '%s' "$out" | wc -L)
  if (( width > columns )); then
    printf '%*s' "$((width - columns))" ''
  fi
fi
printf '%s\n' "$out"
