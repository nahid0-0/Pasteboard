#!/bin/bash
# Renders the Pasteboard product video from the raw screen recording.
#
#   ./Video/edit/render.sh            -> Video/out/Pasteboard-demo.mp4  (1920x1080, 60 fps)
#
# Frame: a 120 px caption bar on top, the footage in the 1920x960 area below it.
# Each scene picks a layout:
#   single  one cropped window, centred
#   side    two crops (Pasteboard + the app you copy from) side by side
#   full    the whole screen (2:1 crop, menu bar excluded unless needed)
# Any scene can slowly zoom into a region and back out (see "zoom" below).
# Scenes are hard cuts — no transitions.
#
# Pieces are source times "start:end:speed[:hold]" (hold = freeze the last frame for N seconds).
# Change a number and re-run. Intermediates go to Video/edit/.build (git-ignored).
set -euo pipefail
export _ZO_DOCTOR=0
cd "$(dirname "$0")/../.."

SRC="Video/PasteBoard product demo.mov"
B=Video/edit/.build
OUT=Video/out
ICON=OmniClip/Assets.xcassets/AppIcon.appiconset/icon_512x512.png
FPS=60
BAR=120
BG=0x0b0d14
mkdir -p "$B/seg" "$OUT"

calc() { printf "%.3f" "$(echo "$1" | bc -l)"; }
even() { echo $(( ($1 / 2) * 2 )); }

# ---------------------------------------------------------------- graphics
echo "🎨 Drawing graphics..."
swiftc -O -o "$B/assets" Video/edit/assets.swift
A="$B/assets"
$A end "$B/end.png" "$ICON"
$A caption "$B/cap_clear.png"  "Clear your clipboard history"
$A caption "$B/cap_copy.png"   "Copy from any app — it shows up in Pasteboard"
$A caption "$B/cap_pin.png"    "Pin it, and it stays open while you work"
$A caption "$B/cap_shot.png"   "Screenshots are saved too"
$A caption "$B/cap_stackon.png" "Stack mode — the blue dot shows it’s on"
$A caption "$B/cap_stack.png"  "Stack text and images"
$A caption "$B/cap_paste.png"  "Paste the stack — text and image together"
$A keys "$B/key_c.png" "⌘" "C"
$A keys "$B/key_v.png" "⌘" "V"
$A keys "$B/key_f.png" "⌘" "⇧" "F"
$A keys "$B/key_4.png" "⌘" "⇧" "4"
$A keys "$B/key_d.png" "⌘" "⇧" "D"

SEGS=()

# ---------------------------------------------------------------- building blocks
# pieces "a:b:speed[:hold] ..." -> appends to FC, output label [src], sets DUR and SS
pieces() {
    local list=$1
    SS=$(echo "$list" | tr ' ' '\n' | cut -d: -f1 | sort -n | head -1)
    local n=0 labels="" parts=""
    DUR=0
    for p in $list; do
        IFS=: read -r a b sp hold <<<"$p"
        local f="[s$n]trim=start=$(calc "$a - $SS"):end=$(calc "$b - $SS"),setpts=(PTS-STARTPTS)/$sp,fps=$FPS"
        [ -n "${hold:-}" ] && f+=",tpad=stop_mode=clone:stop_duration=$hold"
        parts+="$f[p$n];"
        labels+="[p$n]"
        DUR=$(calc "$DUR + ($b - $a) / $sp + ${hold:-0}")
        n=$((n + 1))
    done
    local split="[0:v]split=$n"; for i in $(seq 0 $((n - 1))); do split+="[s$i]"; done
    FC+="$split;$parts${labels}concat=n=$n:v=1:a=0[src];"
}

# camera: crop a source rect and scale it to WxH, optionally zooming into a sub-rect and back.
# cam in out crop(w:h:x:y) W H [bx:by:bw:t1:t2:t3:t4]   (bx,by relative to the crop; same aspect)
# e(t) eases 0->1 between t1..t2 and back 1->0 between t3..t4 (output time)
cam() {
    local in=$1 out=$2 crop=$3 W=$4 H=$5 zoom=${6:-}
    if [ -z "$zoom" ]; then
        FC+="[$in]crop=$crop,scale=$W:$H:flags=lanczos[$out];"
        return
    fi
    local cw=${crop%%:*}
    IFS=: read -r bx by bw t1 t2 t3 t4 <<<"$zoom"
    local e="(st(1,clip((t-$t1)/($t2-$t1),0,1))*ld(1)*(3-2*ld(1))-st(2,clip((t-$t3)/($t4-$t3),0,1))*ld(2)*(3-2*ld(2)))"
    local k="($cw/($cw+($bw-$cw)*$e))"
    # in the overlay, recover progress from the scaled width: visible width = cw*W/w
    local e2="(($cw-$cw*$W/w)/($cw-$bw))"
    FC+="[$in]crop=$crop,scale=w='trunc($W*$k/2)*2':h='trunc($H*$k/2)*2':eval=frame:flags=lanczos[z$out];"
    FC+="color=c=black:s=${W}x${H}:r=$FPS:d=$DUR[cv$out];"
    FC+="[cv$out][z$out]overlay=x='-$bx*$e2*w/$cw':y='-$by*$e2*w/$cw':eval=frame:shortest=1[$out];"
}

# caption bar + key caps on top of [frame]; then encode
finish() { # name caption keyspecs...
    local name=$1 cap=$2; shift 2
    INPUTS+=(-loop 1 -framerate $FPS -t "$DUR" -i "$cap")
    local idx=$(( ${#INPUTS[@]} / 6 - 1 ))  # each image input adds 6 args; source adds 4 (see below)
    idx=$NEXT; NEXT=$((NEXT + 1))
    FC+="[$idx:v]format=rgba[cap];[frame][cap]overlay=0:0[k0];"
    local cur=k0 k=0
    for spec in "$@"; do
        IFS=: read -r kp ks kd <<<"$spec"
        INPUTS+=(-loop 1 -framerate $FPS -t "$DUR" -i "$kp")
        FC+="[$NEXT:v]format=rgba,fade=in:st=$ks:d=0.12:alpha=1,fade=out:st=$(calc "$ks + $kd - 0.2"):d=0.2:alpha=1[kc$k];"
        FC+="[$cur][kc$k]overlay=0:0[kk$k];"
        cur="kk$k"; NEXT=$((NEXT + 1)); k=$((k + 1))
    done
    FC+="[$cur]format=yuv420p[out]"
    local f="$B/seg/$name.mp4"
    echo "🎬 $name (${DUR}s)"
    ffmpeg -v error -y "${INPUTS[@]}" -filter_complex "$FC" -map "[out]" -t "$DUR" \
        -c:v libx264 -crf 16 -preset fast -r $FPS "$f"
    SEGS+=("$f")
}

start() { # pieces
    FC=""; pieces "$1"
    INPUTS=(-ss "$SS" -i "$SRC"); NEXT=1
    FC+="color=c=$BG:s=1920x1080:r=$FPS:d=$DUR[canvas];"
}

# --- layouts -------------------------------------------------------------
# full: 2:1 crop filling the footage area
full() { # name caption pieces crop zoom keys...
    local name=$1 cap=$2; start "$3"; local crop=$4 zoom=$5; shift 5
    cam src v "$crop" 1920 960 "$zoom"
    FC+="[canvas][v]overlay=0:$BAR:shortest=1[frame];"
    finish "$name" "$cap" "$@"
}

# single: one crop, fitted (max 1840x900) and centred
single() { # name caption pieces crop zoom keys...
    local name=$1 cap=$2; start "$3"; local crop=$4 zoom=$5; shift 5
    local w h; IFS=: read -r w h _ _ <<<"$crop"
    local W H
    W=$(awk -v w=$w -v h=$h 'BEGIN{s=1840/w; if (900/h<s) s=900/h; print int(w*s/2)*2}')
    H=$(awk -v w=$w -v h=$h 'BEGIN{s=1840/w; if (900/h<s) s=900/h; print int(h*s/2)*2}')
    cam src v "$crop" "$W" "$H" "$zoom"
    FC+="[canvas][v]overlay=(W-w)/2:$BAR+(960-h)/2:shortest=1[frame];"
    finish "$name" "$cap" "$@"
}

# side: two crops at the same height, 40 px margins and gap
side() { # name caption pieces cropL cropR keys...
    local name=$1 cap=$2; start "$3"; local cl=$4 cr=$5; shift 5
    local wl hl wr hr; IFS=: read -r wl hl _ _ <<<"$cl"; IFS=: read -r wr hr _ _ <<<"$cr"
    local H WL WR
    H=$(awk -v a=$wl -v b=$hl -v c=$wr -v d=$hr 'BEGIN{h=1800/(a/b+c/d); if (h>900) h=900; print int(h/2)*2}')
    WL=$(even "$(awk -v a=$wl -v b=$hl -v h=$H 'BEGIN{print int(a*h/b)}')")
    WR=$(even "$(awk -v c=$wr -v d=$hr -v h=$H 'BEGIN{print int(c*h/d)}')")
    local gap=$(( (1920 - WL - WR) / 3 ))
    FC+="[src]split=2[sl][sr];"
    cam sl L "$cl" "$WL" "$H"
    cam sr R "$cr" "$WR" "$H"
    local y=$(( BAR + (960 - H) / 2 ))
    FC+="[canvas][L]overlay=$gap:$y:shortest=1[c1];[c1][R]overlay=$((gap * 2 + WL)):$y:shortest=1[frame];"
    finish "$name" "$cap" "$@"
}

# ---------------------------------------------------------------- crops (w:h:x:y in the 4076x2844 source)
W_CLEAR=1810:1310:340:950     # Pasteboard window at the start, incl. the Clear menu under it
W_A1=1798:1200:716:831        # window, first position (copy scene)
ED_TOP=1020:1440:2240:440     # editor: the two snippets copied first
W_A2=1798:1200:401:863        # window after it was moved (stack scene)
ED_MID=1020:1040:2240:780     # editor: the stack selections + screenshot area
CHAT=1590:1120:300:1660       # chat box with the pasted stack
FULL=4076:2038:0:380          # whole screen, menu bar excluded
FULL_TOP=4076:2038:0:0        # whole screen incl. menu bar (stack-mode dot)

# ---------------------------------------------------------------- SCENES
# 1. Clear history: menu opens 3.6, "Clear All" 6.1, list empty 6.4 (window hides at 7.4 — cut before).
#    Zoom slowly into the clear button + menu, back out once the list is empty, hold the empty window.
single 01_clear "$B/cap_clear.png" "0.6:7.3:1:1.2" "$W_CLEAR" "260:803:700:2.4:3.6:5.6:6.6"

# 2. Copy text: editor selection 9.7–11.1, ⌘⇧F 12.6 (clip is there); second selection 17.3–17.8, ⌘⇧F 19.4.
side 02_copy "$B/cap_copy.png" \
     "9.4:11.8:1 12.3:14.6:1 17.0:18.2:1 19.2:21.0:1" "$W_A1" "$ED_TOP" \
     "$B/key_c.png:1.9:0.9" "$B/key_f.png:2.55:1.1" "$B/key_c.png:5.4:0.8" "$B/key_f.png:5.95:1.1"

# 3. Pin: hover 21.5, click 22.4 (icon turns blue), window dragged 22.9–23.6, then a selection in the
#    editor at 26.5 — the window stays open — and the copy lands 28.0. Zoom on the pin button.
full 03_pin "$B/cap_pin.png" \
     "21.0:23.8:1 23.8:26.2:2 26.2:29.0:1" "$FULL" "1907:302:1000:0.3:1.2:1.9:2.8" \
     "$B/key_c.png:5.3:0.9"

# 4. Screenshot: ⌘⇧4 40.1, capture 40.3–42.6, lands 44.2. Zoom into the window as it lands.
full 04_screenshot "$B/cap_shot.png" \
     "39.8:45.8:1" "$FULL" "100:482:2400:3.4:4.4:99:100" \
     "$B/key_4.png:0.25:1.1"

# 5a. Stack mode on: ⌘⇧D 46.4, blue dot on the menu bar icon 46.7. Slow zoom in, hold, slow zoom out.
full 05_stackon "$B/cap_stackon.png" \
     "46.0:47.6:1:3.6" "$FULL_TOP" "1948:0:600:0.2:1.6:3.4:4.8" \
     "$B/key_d.png:0.3:1.3"

# 5b. Stack fills: empty stack, selection 51.7 -> lands 54.7, selection 55.3 -> lands 58.1,
#     ⌘⇧4 60.1 on the editor -> lands 62.0.
side 06_stack "$B/cap_stack.png" \
     "47.9:49.0:1 51.4:52.8:1 54.2:55.3:1 55.3:56.1:1 57.6:58.7:1 60.0:62.7:1" "$W_A2" "$ED_MID" \
     "$B/key_c.png:2.5:0.8" "$B/key_c.png:4.4:0.8" "$B/key_4.png:5.6:1.1"

# 5c. The paste result only (text and image in the chat box), no window moving.
single 07_paste "$B/cap_paste.png" "70.9:74.5:1" "$CHAT" "" "$B/key_v.png:0.2:1.2"

# end card
ffmpeg -v error -y -loop 1 -framerate $FPS -t 2.0 -i "$B/end.png" \
    -vf "format=yuv420p" -c:v libx264 -crf 16 -preset fast -r $FPS "$B/seg/08_end.mp4"
SEGS+=("$B/seg/08_end.mp4")

# ---------------------------------------------------------------- assemble (hard cuts)
echo "🧩 Assembling..."
inputs=(); fc=""
for i in "${!SEGS[@]}"; do inputs+=(-i "${SEGS[$i]}"); fc+="[$i:v]"; done
fc+="concat=n=${#SEGS[@]}:v=1:a=0,format=yuv420p[out]"
ffmpeg -v error -y "${inputs[@]}" -filter_complex "$fc" -map "[out]" \
    -c:v libx264 -crf 18 -preset slow -profile:v high -r $FPS -movflags +faststart "$OUT/Pasteboard-demo.mp4"

echo "✅ $OUT/Pasteboard-demo.mp4 ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/Pasteboard-demo.mp4")s)"
