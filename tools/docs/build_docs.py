#!/usr/bin/env python3
"""Builds docs/index.html: the whole record of Last Lift in one file.

Every game of Luqman's keeps one living HTML record - the idea, the planning,
every decision and method, the session logs, and the screenshots with their
explanations - held in the repo and read as a website. This is the generator:
the project notes stay the source of truth and the page is rebuilt from them.

    python3 tools/docs/build_docs.py
    python3 tools/docs/build_docs.py --publish      # and gather it into the local records site

Nothing is deployed: `docs-site` only collects every project's record into one
folder on this machine (`docs-site open` opens it).

The machinery here - the markdown converter, the image embedding, the page
template - was copied from paint-the-dark's build_docs.py (itself from snapshot's). Only the data tables below
are this game's own.

Reads:
    ~/.claude/knowledge/projects/last-lift/*.md and log/*.md   (override: KNOWLEDGE=...)
    dev/shots/*.png                                                (the galleries below)
    dev/checks/*.gd, dev/looks/*.gd                                (their ## headers)
    git log

Writes docs/index.html, fully self-contained: every screenshot is embedded as a
JPEG. No packages beyond the standard library; `sips`, built into macOS, does
the shrinking.

The screenshots are git-ignored, so take them first:

    /Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 1920x1080 -- \
        --shots=dev/shots --host --bots=7 --autostart --autopilot --careful \
        --rooms=office,fire,zoo,office,zoo --rounds=1 --quit
    /Applications/Godot.app/Contents/MacOS/Godot --path . --resolution 1920x1080 -- --shots=dev/shots --menu
"""

import base64
import datetime
import html
import os
import pathlib
import re
import subprocess
import tempfile

PROJECT = pathlib.Path(__file__).resolve().parents[2]
KNOWLEDGE = pathlib.Path(os.environ.get(
    "KNOWLEDGE", pathlib.Path.home() / ".claude/knowledge/projects/last-lift"))
OUT = PROJECT / "docs" / "index.html"
SHOTS = PROJECT / "dev" / "shots"
IMAGE_WIDTH = 880
IMAGE_QUALITY = 62

missing = []
_cache = pathlib.Path(tempfile.gettempdir()) / "last-lift-docs-images"
_cache.mkdir(exist_ok=True)


GALLERIES = [
    ("screens-cab", "The cab", "Everything starts and ends inside a 4 by 4 metre steel elevator. It never moves: the fall is shake, flickering lights and the floor display counting down, and each floor is built in front of the doors while they are shut.", [
        ("01_menu", "The title screen, over the cab at floor 40 with its doors shut and the light flickering."),
        ("02_lobby", "The lobby: eight players squeezed into the cab before the round. The host sees the bot count, the Start button and the address friends type to join."),
        ("03_falling", "Falling between floors. The display counts down, the cab shakes and the light stutters."),
    ]),
    ("screens-office", "Office Party", "Desks, balloons, a retirement banner for Gary and a conga line of six partygoers looping round the cake table. Touch the line and you are knocked aside and may drop what you hold.", [
        ("11_office_doors_open", "The doors open on floor 34. Loot shows its points floating above it."),
        ("11_office_looting", "Seven seconds left. Players carry their loot as a tower on their heads, so everyone can see who is greedy."),
        ("11_office_last_seconds", "The last seconds: the clock goes red and ticks."),
    ]),
    ("screens-fire", "Server Farm Fire", "Four rows of racks. From three seconds in, the fire catches the back row and moves one row toward the doors every three seconds, burning any loot on the floor. Standing in it throws you toward the cab and costs you an item.", [
        ("12_fire_doors_open", "The doors open on the server room."),
        ("12_fire_looting", "In the aisles while the back rows burn."),
        ("12_fire_last_seconds", "The fire has reached row three and the crowd is back in the cab."),
    ]),
    ("screens-zoo", "Rooftop Zoo", "An open rooftop with pens, a pond and a skyline. Two seconds after the doors open the gorilla leaves its rocks and chases whoever is nearest outside the cab; a slam sends you flying and drops your loot.", [
        ("13_zoo_doors_open", "The doors open onto the roof."),
        ("13_zoo_looting", "The gorilla is out and coming for whoever is nearest. Behind it, the crowd already back in the cab."),
        ("13_zoo_last_seconds", "The last seconds on the roof."),
    ]),
    ("screens-end", "The lobby", "After the last stop the cable gives and the cab drops to the ground floor. Whoever is still inside cashes in what they carry.", [
        ("40_crash", "The cable snaps after the last stop: the display races to L and the cab shakes hardest."),
        ("41_results", "The results: this round's haul, the session total, and who made it."),
    ]),
]


# Galleries shown one picture per row, because they hold diagrams with text in them.
SINGLE = {"floorplan"}


NOTES = [
    ("idea", "Idea", "01-idea.md", None),
    ("planning", "Planning", "02-planning.md", 2),
    ("milestones", "Milestones", "03-milestones.md", 2),
    ("decisions", "Decisions", "06-decisions.md", 2),
    ("methods", "Methods", "04-methods.md", 2),
    ("relations", "Relations", "05-relations.md", None),
    ("references", "References", "07-references.md", 2),
]


# --- markdown ------------------------------------------------------------------------------

def inline(text):
    """The inline half of markdown, on already-escaped text."""
    codes = []

    def keep(m):
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"

    text = re.sub(r"`([^`]+)`", keep, text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)",
                  lambda m: f'<a href="{m.group(2)}">{m.group(1)}</a>'
                  if m.group(2).startswith(("http://", "https://")) else m.group(1), text)
    text = re.sub(r"(?<![\w&])(https?://[^\s<)]+)", r'<a href="\1">\1</a>', text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"~~(.+?)~~", r"<del>\1</del>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?!\w)", r"<em>\1</em>", text)
    text = re.sub(r"(?<![\w])_(?!\s)(.+?)(?<!\s)_(?![\w])", r"<em>\1</em>", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: f"<code>{codes[int(m.group(1))]}</code>", text)


def slug(text, taken):
    base = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:60] or "section"
    name, n = base, 2
    while name in taken:
        name, n = f"{base}-{n}", n + 1
    taken.add(name)
    return name


def markdown(source, prefix, taken, fold=None, drop_title=True):
    """Converts one notes file. Headings at `fold` open a <details> that holds everything
    until the next heading at that level or above."""
    source = re.sub(r"\A---\n.*?\n---\n", "", source, flags=re.S)
    lines = source.split("\n")
    out, para, lists, open_folds = [], [], [], 0
    i = 0

    def flush_para():
        if para:
            out.append("<p>" + inline(html.escape(" ".join(para), quote=False)) + "</p>")
            para.clear()

    def close_lists(to=0):
        while len(lists) > to:
            out.append(f"</{lists.pop()[0]}>")

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("```"):
            flush_para(); close_lists()
            block = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                block.append(lines[i])
                i += 1
            out.append("<pre><code>" + html.escape("\n".join(block)) + "</code></pre>")
            i += 1
            continue

        heading = re.match(r"^(#{1,4})\s+(.*)$", line)
        if heading:
            flush_para(); close_lists()
            level = len(heading.group(1))
            title = heading.group(2).strip()
            if level == 1 and drop_title:
                i += 1
                continue
            if fold is not None and level <= fold:
                while open_folds:
                    out.append("</div></details>")
                    open_folds -= 1
            anchor = slug(f"{prefix}-{title}", taken)
            if fold is not None and level == fold:
                out.append(f'<details class="fold" id="{anchor}"><summary><span>'
                           f"{inline(html.escape(title, quote=False))}</span></summary><div>")
                open_folds += 1
            else:
                tag = min(level + 1, 5)
                out.append(f'<h{tag} id="{anchor}">{inline(html.escape(title, quote=False))}</h{tag}>')
            i += 1
            continue

        if stripped.startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            flush_para(); close_lists()
            def cells(row):
                return [c.strip() for c in row.strip().strip("|").split("|")]
            head = cells(line)
            i += 2
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(cells(lines[i]))
                i += 1
            out.append('<div class="table"><table><thead><tr>' + "".join(
                f"<th>{inline(html.escape(c, quote=False))}</th>" for c in head) + "</tr></thead><tbody>")
            for row in rows:
                out.append("<tr>" + "".join(
                    f"<td>{inline(html.escape(c, quote=False))}</td>" for c in row) + "</tr>")
            out.append("</tbody></table></div>")
            continue

        item = re.match(r"^(\s*)([-*]|\d+\.)\s+(\[[ xX]\]\s+)?(.*)$", line)
        if item:
            flush_para()
            depth = len(item.group(1)) // 2
            kind = "ol" if item.group(2)[0].isdigit() else "ul"
            while len(lists) > depth + 1:
                out.append(f"</{lists.pop()[0]}>")
            if len(lists) == depth + 1 and lists[-1][0] != kind:
                out.append(f"</{lists.pop()[0]}>")
            if len(lists) < depth + 1:
                out.append(f"<{kind}>")
                lists.append((kind, depth))
            box = item.group(3)
            mark = ""
            if box:
                mark = '<span class="box done">done</span> ' if "x" in box.lower() else '<span class="box">to do</span> '
            text = item.group(4)
            # A continuation line indented under the item belongs to it.
            while i + 1 < len(lines) and lines[i + 1].startswith(" " * (len(item.group(1)) + 2)) \
                    and lines[i + 1].strip() and not lines[i + 1].strip().startswith("|") \
                    and not re.match(r"^\s*([-*]|\d+\.)\s+", lines[i + 1]):
                i += 1
                text += " " + lines[i].strip()
            out.append(f"<li>{mark}{inline(html.escape(text, quote=False))}</li>")
            i += 1
            continue

        if stripped.startswith(">"):
            flush_para(); close_lists()
            quote = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip()[1:].strip())
                i += 1
            out.append("<blockquote>" + inline(html.escape(" ".join(quote), quote=False)) + "</blockquote>")
            continue

        if re.match(r"^\s*(---|\*\*\*)\s*$", line):
            flush_para(); close_lists()
            i += 1
            continue

        if not stripped:
            flush_para()
            if not (i + 1 < len(lines) and re.match(r"^\s+([-*]|\d+\.)\s+", lines[i + 1])):
                close_lists()
            i += 1
            continue

        if lists and line.startswith("  ") and not stripped.startswith("|"):
            # Loose text under a list item.
            out[-1] = out[-1].replace("</li>", " " + inline(html.escape(stripped, quote=False)) + "</li>")
            i += 1
            continue

        close_lists()
        para.append(stripped)
        i += 1

    flush_para(); close_lists()
    while open_folds:
        out.append("</div></details>")
        open_folds -= 1
    return "\n".join(out)


# --- pictures ----------------------------------------------------------------------------

_cache = pathlib.Path(tempfile.gettempdir()) / "last-lift-docs-images"
_cache.mkdir(exist_ok=True)
missing = []


def picture(name):
    """(data URI, date) for a screenshot, or (None, None) when it is not there."""
    path = PROJECT / name if "/" in name else SHOTS / f"{name}.png"
    if not path.exists():
        missing.append(name)
        return None, None
    stamp = int(path.stat().st_mtime)
    jpeg = _cache / f"{path.stem}-{stamp}.jpg"
    if not jpeg.exists():
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(IMAGE_QUALITY),
                        "-Z", str(IMAGE_WIDTH), str(path), "--out", str(jpeg)],
                       check=True, capture_output=True)
    data = base64.b64encode(jpeg.read_bytes()).decode()
    return f"data:image/jpeg;base64,{data}", datetime.date.fromtimestamp(stamp).isoformat()


def figure(name, caption, label=""):
    uri, date = picture(name)
    if uri is None:
        return (f'<figure class="shot missing"><div class="gap">Screenshot not taken yet: '
                f"<code>{html.escape(name)}</code></div><figcaption>{html.escape(caption)}</figcaption></figure>")
    stamp = f'<span class="tc">{html.escape(label)}</span>' if label else ""
    return (f'<figure class="shot"><img src="{uri}" alt="{html.escape(caption)}" loading="lazy" '
            f'width="{IMAGE_WIDTH}" height="{IMAGE_WIDTH * 9 // 16}"><figcaption>{stamp}'
            f'<span>{html.escape(caption)}</span><span class="date">{date}</span></figcaption></figure>')


def grid(figures, single=False):
    if single:
        return f'<div class="shots single">{"".join(figures)}</div>'
    return f'<div class="shots{" odd" if len(figures) % 2 else ""}">{"".join(figures)}</div>'


# --- the facts that can be counted ---------------------------------------------------------

def git(*args):
    return subprocess.run(["git", *args], cwd=PROJECT, capture_output=True, text=True).stdout


def counts():
    return [
        ("Rooms", "3"),
        ("Players", "up to 12"),
        ("Loot kinds", str(len(re.findall(r'^\t"\w+": +\[', (PROJECT / "scripts" / "rules.gd").read_text(), re.M)))),
        ("Scripts", str(len(list((PROJECT / "scripts").rglob("*.gd"))))),
        ("Check rules", str(sum(len(re.findall(r"\bcheck\(\"", p.read_text())) for p in (PROJECT / "dev" / "checks").glob("*.*") if p.suffix in (".gd", ".sh")))),
        ("Commits", git("rev-list", "--count", "HEAD").strip() or "0"),
        ("Decisions", str(len(re.findall(r"^## ", (KNOWLEDGE / "06-decisions.md").read_text(), re.M)))),
    ]


def header_comment(path):
    lines = []
    for line in path.read_text().split("\n"):
        if line.startswith("##"):
            text = line[2:].strip()
            if not text and lines:
                break
            if text:
                lines.append(text)
        elif lines:
            break
    return " ".join(lines)


def catalogue(folder):
    rows = []
    for path in sorted(p for p in (PROJECT / "dev" / folder).glob("*.*") if p.suffix in (".gd", ".sh")):
        rows.append(f"<tr><td><code>{path.stem}</code></td>"
                    f"<td>{inline(html.escape(header_comment(path) or '—', quote=False))}</td></tr>")
    return '<div class="table"><table><thead><tr><th>File</th><th>What it asks</th></tr></thead><tbody>' \
        + "".join(rows) + "</tbody></table></div>"


def history():
    rows = []
    for line in git("log", "--date=short", "--pretty=format:%h\t%ad\t%s").split("\n"):
        if not line:
            continue
        sha, date, subject = line.split("\t", 2)
        merge = " merge" if subject.lower().startswith("merge") else ""
        rows.append(f'<tr class="{merge.strip()}"><td><code>{sha}</code></td><td class="nowrap">{date}</td>'
                    f"<td>{html.escape(subject)}</td></tr>")
    return '<div class="table"><table><thead><tr><th>Commit</th><th>Date</th><th>Change</th></tr></thead><tbody>' \
        + "".join(rows) + "</tbody></table></div>"


# --- the page ----------------------------------------------------------------------------------

PIPELINE = [
    ("Ideas", "Free-to-play game ideas, then fresh ones from the 2026 market, then online ones; Luqman picked Last Lift.", "log/2026-10-06.md"),
    ("Concept page", "The pitch as a page with a playable mock round, the floor deck, the HUD and the shop.", "07-references.md"),
    ("Decide", "Godot 4 low-poly 3D, host/join by IP with bots, third-person, core loop and three rooms.", "06-decisions.md"),
    ("Build", "Cab, rooms, players, bots, networking and HUD, all built in code from primitives.", "scripts/"),
    ("Check", "Every room and seed has reachable loot; a real headless network round with two clients agrees on the results.", "dev/checks/"),
    ("Look", "A windowed round with bots photographed at each moment, then read back and fixed.", "dev/looks/shots.gd, dev/shots/"),
    ("Play", "Luqman plays it, then friends - the part nothing automatic can do.", "log/"),
]


TOOLS = [
    ("Godot 4.7.2", "Engine, Forward+. High-level multiplayer over ENet, NavigationServer3D baked at runtime per room, Label3D for names and loot values."),
    ("GDScript", "All of it, including every model: the cab, the rooms, the people and the gorilla are primitives placed in code."),
    ("Kenney audio (CC0)", "Seventeen sounds from the Interface, Impact, Sci-fi and Music Jingles packs, fetched with the sfx CLI."),
    ("Bungee", "Elevator-signage display face for headings. SIL Open Font License."),
    ("Chakra Petch", "The floor display and every other label. SIL Open Font License."),
    ("Knowledge base", "The project notes this page is built from, kept outside the repo."),
]


def page():
    taken = set()
    overview = (KNOWLEDGE / "00-overview.md").read_text()
    thesis = re.search(r"^# last-lift — Overview\n\n(.+?)(?=\n\n)", overview, re.S | re.M)
    thesis = " ".join(l.strip() for l in thesis.group(1).split("\n")) if thesis else ""
    built = datetime.date.today().isoformat()

    toc, body = [], []

    # Cover
    stats = "".join(f'<div class="stat"><b>{v}</b><span>{k}</span></div>' for k, v in counts())
    uri, _ = picture("11_office_doors_open")
    hero = (f'<img class="hero" src="{uri}" alt="The elevator doors open on an office party, players crowding out to grab loot" '
            f'width="{IMAGE_WIDTH}" height="495">') if uri else ""
    body.append(f'''
<header class="cover" id="top">
  <p class="eyebrow"><b>Last Lift</b><span>Project record · built {built}</span></p>
  <h1>Last Lift</h1>
  <p class="thesis">{inline(html.escape(thesis, quote=False))}</p>
  <div class="stats">{stats}</div>
  {hero}
</header>''')

    # Pipeline
    toc.append(("pipeline", "Pipeline", []))
    steps = "".join(f'<li><b>{html.escape(a)}</b><span>{html.escape(b)}</span><code>{html.escape(c)}</code></li>'
                    for a, b, c in PIPELINE)
    tools = "".join(f"<tr><td><strong>{html.escape(a)}</strong></td><td>{html.escape(b)}</td></tr>" for a, b in TOOLS)
    body.append(f'''
<section class="chapter" id="pipeline">
  <p class="kicker">How the game got made</p>
  <h2>Pipeline</h2>
  <p class="lede">The idea came out of a conversation about free games that make money, went through a concept page, and was built as a first playable in one session. Every number the game is balanced on lives in one file, scripts/rules.gd.</p>
  <ol class="pipeline">{steps}</ol>
  <h3 id="tools">Tools</h3>
  <div class="table"><table><tbody>{tools}</tbody></table></div>
</section>''')

    # Screens
    subs, parts = [], []
    for gid, title, intro, shots in GALLERIES:
        subs.append((gid, title))
        parts.append(f'<section class="gallery" id="{gid}"><h3>{html.escape(title)}</h3>'
                     f'<p class="note">{html.escape(intro)}</p>{grid([figure(n, c) for n, c in shots], gid in SINGLE)}</section>')
    toc.append(("screens", "Screens", subs))
    body.append(f'''
<section class="chapter" id="screens">
  <p class="kicker">What the player sees</p>
  <h2>Screens</h2>
  <p class="lede">Every screenshot here comes from a real hosted round with seven bots and the host on autopilot, photographed at fixed moments by dev/looks/shots.gd. The first pass showed what the code did not: the door clock and the camera label sat on top of the floor panel, and name tags filled half the screen inside the crowded cab.</p>
  {"".join(parts)}
</section>''')

    # The notes
    for nid, title, name, fold in NOTES:
        path = KNOWLEDGE / name
        if not path.exists():
            continue
        text = path.read_text()
        converted = markdown(text, nid, taken, fold)
        heads = [h for h in re.findall(r"^## (.+)$", re.sub(r"```.*?```", "", text, flags=re.S), re.M)]
        folds = ' <button class="unfold" type="button" data-for="%s">Open all</button>' % nid if fold else ""
        toc.append((nid, title, []))
        body.append(f'''
<section class="chapter notes" id="{nid}">
  <p class="kicker">{html.escape(name)} · {len(heads)} sections{folds}</p>
  <h2>{html.escape(title)}</h2>
  <div class="prose">{converted}</div>
</section>''')

    # Logs
    logs = sorted((p for p in (KNOWLEDGE / "log").glob("*.md") if not p.name.startswith("_")), reverse=True)
    entries = "".join(
        f'<details class="fold" id="log-{p.stem}"><summary><span>{p.stem}</span></summary>'
        f'<div>{markdown(p.read_text(), "log-" + p.stem, taken, None)}</div></details>'
        for p in logs)
    toc.append(("log", "Session log", []))
    body.append(f'''
<section class="chapter notes" id="log">
  <p class="kicker">log/ · {len(logs)} sessions <button class="unfold" type="button" data-for="log">Open all</button></p>
  <h2>Session log</h2>
  <div class="prose">{entries}</div>
</section>''')

    # Catalogues
    toc.append(("checks", "Checks and looks", []))
    body.append(f'''
<section class="chapter" id="checks">
  <p class="kicker">dev/checks and dev/looks, from each scene\'s own header</p>
  <h2>Checks and looks</h2>
  <p class="lede">A check runs and ends in a verdict. A look takes screenshots for a person to judge. The room check bakes each room's navmesh and walks from the cab to every loot spot; it found desk tops baking as islands and a rooftop wall blocking the doorway. The network check runs a host and two clients as separate processes and compares their results.</p>
  <details class="fold"><summary><span>Checks</span></summary><div>{catalogue("checks")}</div></details>
  <details class="fold"><summary><span>Looks</span></summary><div>{catalogue("looks")}</div></details>
</section>''')
    toc.append(("history", "Git history", []))
    body.append(f'''
<section class="chapter" id="history">
  <p class="kicker">git log, newest first</p>
  <h2>Git history</h2>
  <details class="fold"><summary><span>Every commit</span></summary><div>{history()}</div></details>
</section>''')

    nav = []
    for tid, title, subs in toc:
        inner = "".join(f'<li><a href="#{sid}">{html.escape(st)}</a></li>' for sid, st in subs)
        nav.append(f'<li><a href="#{tid}">{html.escape(title)}</a>{f"<ul>{inner}</ul>" if inner else ""}</li>')

    return TEMPLATE.replace("{{NAV}}", "".join(nav)).replace("{{BODY}}", "".join(body))


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Last Lift Record</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@600;700&family=IBM+Plex+Mono:wght@500&family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;1,400&display=swap">
<style>
:root {
  --ground: #FAF7F2; --surface: #FFFFFF; --ink: #2B2622; --muted: #6B6259; --line: #E7E1D8;
  --court: #2F6BB0; --court-soft: #D6E6FA; --caption: #FFEEC9; --caption-ink: #A97B12;
  --done: #2F7A5C; --display: "Barlow Condensed", "Arial Narrow", "Helvetica Neue", Arial, sans-serif;
  --body: "IBM Plex Sans", "Helvetica Neue", Arial, sans-serif; --mono: "IBM Plex Mono", ui-monospace, Menlo, monospace;
  color-scheme: light;
}
@media (prefers-color-scheme: light) {
  :root:not([data-theme="light"]) { --ground: #FAF7F2; --surface: #FFFFFF; --ink: #2B2622; --muted: #6B6259;
    --line: #E7E1D8; --court: #2F6BB0; --court-soft: #D6E6FA; --done: #2F7A5C; color-scheme: light; }
}
:root[data-theme="dark"] { --ground: #FAF7F2; --surface: #FFFFFF; --ink: #2B2622; --muted: #6B6259;
  --line: #E7E1D8; --court: #2F6BB0; --court-soft: #D6E6FA; --done: #2F7A5C; color-scheme: light; }
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
@media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
body { margin: 0; background: var(--ground); color: var(--ink); font: 400 16px/1.6 var(--body); padding-inline: 20px; }
a { color: var(--court); }
a:focus-visible, button:focus-visible, summary:focus-visible { outline: 2px solid var(--court); outline-offset: 2px; }
.layout { max-width: 1320px; margin: 0 auto; display: grid; grid-template-columns: 220px minmax(0, 1fr); gap: 48px; padding-block: 32px 96px; }
nav.toc { position: sticky; top: calc(env(safe-area-inset-top, 0px) + 20px); align-self: start; max-height: calc(100vh - 40px); overflow-y: auto; font-size: 14px; }
nav.toc > ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 4px; }
nav.toc > ul > li > a { font: 700 16px/1.3 var(--display); letter-spacing: .06em; text-transform: uppercase; color: var(--ink); text-decoration: none; }
nav.toc ul ul { list-style: none; margin: 2px 0 8px; padding: 0 0 0 10px; border-left: 1px solid var(--line); display: grid; gap: 1px; }
nav.toc ul ul a { color: var(--muted); text-decoration: none; }
nav.toc a:hover { color: var(--court); }
main { display: grid; gap: 72px; min-width: 0; }
.eyebrow { display: inline-flex; gap: 10px; align-items: center; margin: 0; font: 700 14px/1 var(--display); letter-spacing: .12em; text-transform: uppercase; }
.eyebrow b { background: var(--caption); color: var(--caption-ink); padding: 5px 9px; }
.eyebrow span { color: var(--muted); }
h1 { font: 700 clamp(44px, 7vw, 84px)/.92 var(--display); text-transform: uppercase; margin: 14px 0 12px; text-wrap: balance; }
.thesis { max-width: 68ch; margin: 0; font-size: 18px; }
.stats { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 0; margin: 28px 0; border-block: 2px solid var(--ink); }
.stat { padding: 12px 14px; display: grid; gap: 2px; border-left: 1px solid var(--line); }
.stat:first-child { border-left: 0; padding-left: 0; }
.stat b { font: 700 34px/1 var(--display); font-variant-numeric: tabular-nums; }
.stat span { font-size: 12px; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); }
.hero { width: 100%; max-width: 100%; height: auto; display: block; }
.chapter { display: grid; gap: 14px; scroll-margin-top: 16px; }
.kicker { margin: 0; font-size: 13px; color: var(--muted); display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
h2 { font: 700 48px/1 var(--display); text-transform: uppercase; margin: 0 0 6px; padding-bottom: 10px; border-bottom: 2px solid var(--ink); }
h3 { font: 700 30px/1.05 var(--display); text-transform: uppercase; margin: 24px 0 4px; scroll-margin-top: 16px; }
h4 { font: 700 21px/1.1 var(--display); text-transform: uppercase; letter-spacing: .02em; margin: 18px 0 8px; }
h4 small { font: 400 14px var(--body); text-transform: none; color: var(--muted); margin-left: 8px; }
h5 { font: 600 16px/1.3 var(--body); margin: 18px 0 4px; }
.lede, .note { max-width: 70ch; margin: 0; color: var(--muted); }
.gallery { scroll-margin-top: 16px; display: grid; gap: 8px; }
.status { font: 500 12px/1 var(--mono); text-transform: none; letter-spacing: 0; color: var(--court); background: var(--court-soft); padding: 4px 8px; vertical-align: middle; }
.shots { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px; margin-top: 10px; }
.shots.odd > .shot:first-child { grid-column: 1 / -1; }
.shots.single { grid-template-columns: minmax(0, 1fr); }
.shots.odd > .shot:first-child img { max-height: 520px; object-fit: cover; }
.shot { margin: 0; display: grid; gap: 6px; align-content: start; }
.shot img { display: block; width: 100%; max-width: 100%; height: auto; background: var(--line); }
.shot figcaption { font-size: 14px; line-height: 1.4; display: grid; grid-template-columns: auto 1fr auto; gap: 10px; align-items: baseline; }
.tc, .date { font: 500 12px/1 var(--mono); color: var(--muted); white-space: nowrap; font-variant-numeric: tabular-nums; }
.missing .gap { aspect-ratio: 16 / 9; display: grid; place-items: center; border: 1px dashed var(--line); color: var(--muted); font-size: 14px; padding: 16px; text-align: center; }
.rules { list-style: none; margin: 8px 0 0; padding: 0; display: grid; gap: 6px; max-width: 80ch; }
.rules li { display: grid; grid-template-columns: 92px 1fr; gap: 12px; font-size: 14.5px; }
.ref { font: 500 12px/1.7 var(--mono); color: var(--court); background: var(--court-soft); text-align: center; align-self: start; }
.pipeline { list-style: none; counter-reset: step; margin: 10px 0 0; padding: 0; display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 0; border-top: 1px solid var(--line); border-left: 1px solid var(--line); }
.pipeline li { counter-increment: step; padding: 14px 16px 16px; display: grid; gap: 4px; align-content: start; border-right: 1px solid var(--line); border-bottom: 1px solid var(--line); background: var(--surface); }
.pipeline b { font: 700 20px/1 var(--display); text-transform: uppercase; }
.pipeline b::before { content: counter(step) "  "; color: var(--court); font-family: var(--mono); font-size: 13px; font-weight: 500; }
.pipeline span { font-size: 14.5px; }
.pipeline code { font-size: 12px; color: var(--muted); justify-self: start; }
.prose { max-width: 82ch; display: grid; gap: 0; }
.prose p, .prose ul, .prose ol, .prose blockquote, .prose pre, .prose .table { margin: 0 0 12px; }
.prose ul, .prose ol { padding-left: 22px; }
.prose li { margin: 3px 0; }
.prose blockquote { border-left: 3px solid var(--caption); padding: 4px 0 4px 14px; color: var(--muted); }
code { font: 500 .86em var(--mono); background: var(--court-soft); padding: 1px 4px; overflow-wrap: anywhere; }
pre { background: var(--surface); border: 1px solid var(--line); padding: 12px 14px; overflow-x: auto; }
pre code { background: none; padding: 0; overflow-wrap: normal; white-space: pre; }
.table { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; font-size: 14px; }
th, td { text-align: left; vertical-align: top; padding: 7px 10px; border-bottom: 1px solid var(--line); }
th { font: 700 14px/1.2 var(--display); letter-spacing: .08em; text-transform: uppercase; color: var(--muted); border-bottom: 2px solid var(--ink); }
.chapter > .table td:first-child { width: 220px; }
tr.merge td { color: var(--muted); }
.nowrap { white-space: nowrap; font-variant-numeric: tabular-nums; }
del { color: var(--muted); }
.box { font: 500 11px/1 var(--mono); padding: 2px 5px; border: 1px solid var(--line); color: var(--muted); vertical-align: 1px; }
.box.done { color: var(--done); border-color: var(--done); }
details.fold { border-bottom: 1px solid var(--line); scroll-margin-top: 16px; }
details.fold > summary { cursor: pointer; list-style: none; padding: 10px 0; display: flex; gap: 10px; align-items: baseline; font: 600 16px/1.35 var(--body); }
details.fold > summary::-webkit-details-marker { display: none; }
details.fold > summary::before { content: "+"; font: 500 14px var(--mono); color: var(--court); width: 12px; flex: none; }
details.fold[open] > summary::before { content: "\\2212"; }
details.fold > div { padding: 2px 0 18px 22px; }
.unfold { font: 600 12px/1 var(--body); color: var(--court); background: var(--surface); border: 1px solid var(--line); padding: 5px 9px; cursor: pointer; }
.unfold:hover { border-color: var(--court); }
@media (max-width: 980px) {
  .layout { grid-template-columns: 1fr; gap: 24px; }
  nav.toc { position: static; max-height: none; border-bottom: 2px solid var(--ink); padding-bottom: 14px; }
  nav.toc > ul { grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); }
  nav.toc ul ul { display: none; }
  .stats { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .stat:nth-child(4) { border-left: 0; padding-left: 0; }
  .pipeline { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
@media (max-width: 560px) {
  .shots { grid-template-columns: 1fr; }
  .pipeline { grid-template-columns: 1fr; }
  h2 { font-size: 38px; }
  .rules li { grid-template-columns: 1fr; gap: 2px; }
  .ref { justify-self: start; padding: 0 6px; }
  .shot figcaption { grid-template-columns: 1fr; gap: 2px; }
}
</style>
</head>
<body>
<div class="layout">
  <nav class="toc" aria-label="Contents"><ul>{{NAV}}</ul></nav>
  <main>{{BODY}}</main>
</div>
<script>
document.querySelectorAll(".unfold").forEach(function (button) {
  button.addEventListener("click", function () {
    var section = document.getElementById(button.dataset.for);
    var folds = section.querySelectorAll("details.fold");
    var opening = button.textContent === "Open all";
    folds.forEach(function (d) { d.open = opening; });
    button.textContent = opening ? "Close all" : "Open all";
  });
});
// A link to something inside a closed fold opens the fold.
function openTarget() {
  var target = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
  for (var node = target; node; node = node.parentElement) {
    if (node.tagName === "DETAILS") node.open = true;
  }
  if (target) target.scrollIntoView();
}
window.addEventListener("hashchange", openTarget);
openTarget();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    import sys
    OUT.parent.mkdir(exist_ok=True)
    document = page()
    OUT.write_text(document)
    if "--publish" in sys.argv:
        subprocess.run(["docs-site", "publish"], check=True)
    size = OUT.stat().st_size / 1024 / 1024
    print(f"wrote {OUT.relative_to(PROJECT)}  ({size:.1f} MB)")
    if missing:
        print("screenshots not found (shown as gaps):", ", ".join(missing))
