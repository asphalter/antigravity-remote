#!/usr/bin/env python3
"""
Customizes KasmVNC Web UI with Google Antigravity IDE branding:
- Replaces KasmVNC favicons with Antigravity icons
- Sets tab title permanently to 'Antigravity'
- Replaces sidebar logo with Antigravity branding card
- Injects FileBrowser Quantum quick-link in the sidebar
- Customizes transition / connecting splash screen with official Antigravity vector logo and 'Connecting...'
"""

import base64
import glob
import os
import re
import shutil
import sys

WWW_DIR = os.environ.get("KASMVNC_WWW_DIR", "/usr/share/kasmvnc/www")
OPT_DIR = os.environ.get("ANTIGRAVITY_OPT_DIR", "/opt/antigravity")

if not os.path.isdir(WWW_DIR):
    print(f"[Brand] Notice: {WWW_DIR} does not exist, skipping branding.")
    sys.exit(0)

assets_dir = os.path.join(WWW_DIR, "assets")
os.makedirs(assets_dir, exist_ok=True)

# 1. Resolve and copy Antigravity official icons
config_dir = os.path.dirname(os.path.abspath(__file__))
potential_pngs = [
    os.path.join("/etc/antigravity", "antigravity.png"),
    os.path.join(config_dir, "antigravity.png"),
    os.path.join(OPT_DIR, "resources/app/resources/linux/code.png"),
    os.path.join(config_dir, "../docs/logo.png"),
]

potential_svgs = [
    os.path.join("/etc/antigravity", "antigravity.svg"),
    os.path.join(config_dir, "antigravity.svg"),
    os.path.join(OPT_DIR, "resources/app/out/vs/platform/browserOnboarding/static/antigravity.svg"),
    os.path.join(config_dir, "../docs/antigravity.svg"),
]

png_path = next((p for p in potential_pngs if os.path.isfile(p)), None)
svg_path = next((p for p in potential_svgs if os.path.isfile(p)), None)

png_data_uri = "./assets/antigravity.png"
svg_data_uri = "./assets/antigravity.svg"

if png_path:
    dest_png = os.path.join(assets_dir, "antigravity.png")
    shutil.copy2(png_path, dest_png)
    for logo_file in glob.glob(os.path.join(assets_dir, "368_kasm_logo_only_*.png")):
        shutil.copy2(dest_png, logo_file)
    with open(png_path, "rb") as f:
        b64_png = base64.b64encode(f.read()).decode("ascii")
        png_data_uri = f"data:image/png;base64,{b64_png}"
    print(f"[Brand] Loaded real Antigravity PNG logo from {png_path} ({len(png_data_uri)} chars)")

if svg_path:
    dest_svg = os.path.join(assets_dir, "antigravity.svg")
    shutil.copy2(svg_path, dest_svg)
    with open(svg_path, "rb") as f:
        b64_svg = base64.b64encode(f.read()).decode("ascii")
        svg_data_uri = f"data:image/svg+xml;base64,{b64_svg}"
    print(f"[Brand] Loaded real Antigravity SVG logo from {svg_path} ({len(svg_data_uri)} chars)")
else:
    svg_data_uri = png_data_uri

# 2. Splash Screen (Transition / Connecting) Configuration
splash_css = """
<style id="antigravity-splash-style">
#noVNC_transition {
    position: fixed !important;
    top: 0 !important; left: 0 !important; bottom: 0 !important; right: 0 !important;
    background: #0f172a !important;
    background-image: none !important;
    color: #f1f5f9 !important;
    display: none;
    flex-direction: column !important;
    align-items: center !important;
    justify-content: center !important;
    z-index: 50 !important;
    transition: opacity 0.8s ease-in-out !important;
}
:root.noVNC_loading #noVNC_transition,
:root.noVNC_connecting #noVNC_transition,
:root.noVNC_disconnecting #noVNC_transition,
:root.noVNC_reconnecting #noVNC_transition {
    display: flex !important;
}
.noVNC_ag_logo_container {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    animation: agPulse 2.5s infinite ease-in-out;
}
.noVNC_ag_logo {
    width: 140px;
    height: 140px;
    object-fit: contain;
    filter: drop-shadow(0 10px 25px rgba(59, 130, 246, 0.3));
}
.noVNC_ag_title {
    color: #ffffff;
    font-size: 26px;
    font-weight: 600;
    letter-spacing: 0.5px;
    margin-top: 16px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
}
#noVNC_transition_text {
    color: #94a3b8 !important;
    font-size: 16px !important;
    font-weight: 500 !important;
    letter-spacing: 0.8px !important;
    margin-top: 14px !important;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
}
.noVNC_ag_spinner {
    display: inline-flex;
    gap: 6px;
    margin-top: 20px;
}
.noVNC_ag_spinner div {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #38bdf8;
    animation: agBounce 1.4s infinite ease-in-out both;
}
.noVNC_ag_spinner div:nth-child(1) { animation-delay: -0.32s; }
.noVNC_ag_spinner div:nth-child(2) { animation-delay: -0.16s; }
@keyframes agBounce {
    0%, 80%, 100% { transform: scale(0); opacity: 0.3; }
    40% { transform: scale(1); opacity: 1; }
}
@keyframes agPulse {
    0%, 100% { transform: scale(1); }
    50% { transform: scale(1.02); }
}
</style>
"""

splash_html = (
    '<div id="noVNC_transition">'
    '<div class="noVNC_ag_logo_container">'
    f'<img class="noVNC_ag_logo" src="{svg_data_uri}" alt="Antigravity">'
    '<div class="noVNC_ag_title">Antigravity</div>'
    '</div>'
    '<div id="noVNC_transition_text">Connecting...</div>'
    '<div><input type="button" id="noVNC_cancel_reconnect_button" value="Cancel" class="noVNC_submit"></div>'
    '<div class="noVNC_ag_spinner"><div></div><div></div><div></div></div>'
    '</div>'
)

# 3. Patch index.html and vnc.html
replacement_logo_html = (
    '<h1 class="noVNC_logo" style="background: rgba(255, 255, 255, 0.08); '
    'border-radius: 8px; padding: 10px 8px; margin: 5px 0 8px 0; display: flex; '
    'align-items: center; justify-content: center; box-shadow: 0 2px 8px rgba(0,0,0,0.2);">'
    '<a href="https://antigravity.google" target="_blank" title="Google Antigravity IDE" '
    'style="display: flex; align-items: center; justify-content: center; text-decoration: none; width: 100%;">'
    f'<img src="{svg_data_uri}" style="width: 28px; height: 28px; object-fit: contain; border-radius: 4px;" alt="Antigravity">'
    '<span style="color: #ffffff; font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif; '
    'font-size: 15px; font-weight: 600; letter-spacing: 0.5px; margin-left: 8px;">Antigravity</span>'
    '</a></h1>'
    '<a href="/filebrowser/" target="_blank" rel="noopener noreferrer" id="noVNC_filebrowser_link" '
    'class="noVNC_button_div" style="display: flex; align-items: center; padding: 8px 10px; margin: 6px 0 10px 0; '
    'background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.12); border-radius: 6px; '
    'color: #ffffff; text-decoration: none; cursor: pointer; transition: all 0.2s ease;" '
    'onmouseover="this.style.background=\'rgba(255, 255, 255, 0.18)\'; this.style.borderColor=\'rgba(255, 255, 255, 0.3)\';" '
    'onmouseout="this.style.background=\'rgba(255, 255, 255, 0.08)\'; this.style.borderColor=\'rgba(255, 255, 255, 0.12)\';" '
    'onclick="event.preventDefault(); var u = \'/filebrowser/\'; if(window.location.port===\'8080\'){ u = window.location.protocol+\'//\'+window.location.hostname+\':8081/filebrowser/\'; } window.open(u, \'_blank\', \'noopener,noreferrer\');" '
    'title="Open Web File Manager in a new window">'
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin-right: 10px; flex-shrink: 0; color: #60a5fa;"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path></svg>'
    '<span style="font-size: 13px; font-weight: 500; letter-spacing: 0.3px; flex-grow: 1;">FileBrowser</span>'
    '<svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="opacity: 0.6; flex-shrink: 0;"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg>'
    '</a>'
)

title_script = (
    '<title>Antigravity</title>'
    f'<link rel="icon" type="image/svg+xml" href="{svg_data_uri}">'
    f'<link rel="icon" type="image/png" href="{png_data_uri}">'
    '<script>document.title="Antigravity";'
    'try{Object.defineProperty(document,"title",{get:function(){return"Antigravity"},set:function(){},configurable:true});}catch(e){}'
    '</script>'
)

for filename in ["index.html", "vnc.html"]:
    filepath = os.path.join(WWW_DIR, filename)
    if not os.path.isfile(filepath):
        continue

    with open(filepath, "r", encoding="utf-8") as f:
        html = f.read()

    # 3a. Title and favicons
    if "<title>KasmVNC</title>" in html:
        html = html.replace("<title>KasmVNC</title>", title_script)
    elif "<title>Antigravity</title>" in html and "antigravity-splash-style" not in html:
        # ensure favicons are fresh
        pass

    # 3b. Sidebar logo and FileBrowser link
    if '<h1 class="noVNC_logo">' in html and 'id="noVNC_filebrowser_link"' not in html:
        html = re.sub(r'<h1 class="noVNC_logo">.*?</h1>', replacement_logo_html, html, count=1, flags=re.DOTALL)

    # 3c. Splash styles injection in <head>
    if "antigravity-splash-style" not in html and "</head>" in html:
        html = html.replace("</head>", f"{splash_css}\n</head>")

    # 3d. Replace transition / connecting splash container in <body>
    target_transition = '<div id="noVNC_transition"><div id="noVNC_transition_text"></div><div><input type="button" id="noVNC_cancel_reconnect_button" value="Cancel" class="noVNC_submit"></div><div class="noVNC_spinner"></div></div>'
    if target_transition in html:
        html = html.replace(target_transition, splash_html)
    elif "noVNC_ag_logo_container" not in html and '<div id="noVNC_transition">' in html:
        transition_pattern = r'<div id="noVNC_transition">.*?<div id="noVNC_container">'
        m = re.search(transition_pattern, html, flags=re.DOTALL)
        if m:
            html = html[:m.start()] + splash_html + html[m.end() - len('<div id="noVNC_container">'):]

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"[Brand] Successfully patched {filename} ({len(html)} bytes)")

# 4. Patch assets/ui-*.css (remove legacy KasmVNC logo background)
for css_file in glob.glob(os.path.join(assets_dir, "ui-*.css")):
    with open(css_file, "r", encoding="utf-8") as f:
        css = f.read()

    # Replace legacy KasmVNC SVG background with clean dark theme color
    css_patched = re.sub(
        r'#noVNC_transition\{[^}]*background:#fff url\("data:image/svg\+xml,[^"]*"\)[^;]*;',
        '#noVNC_transition{background:#0f172a;',
        css
    )
    if css_patched != css:
        with open(css_file, "w", encoding="utf-8") as f:
            f.write(css_patched)
        print(f"[Brand] Successfully stripped KasmVNC SVG background from {os.path.basename(css_file)}")

# 5. Patch assets/ui-*.js (title strings)
for js_file in glob.glob(os.path.join(assets_dir, "ui-*.js")):
    with open(js_file, "r", encoding="utf-8") as f:
        js = f.read()

    modified = False
    if 'const Sx="KasmVNC"' in js:
        js = js.replace('const Sx="KasmVNC"', 'const Sx="Antigravity"')
        modified = True
    if 'document.title=n.detail.name+" - "+Sx' in js:
        js = js.replace('document.title=n.detail.name+" - "+Sx', 'document.title="Antigravity"')
        modified = True
    if 'document.title=Sx' in js:
        js = js.replace('document.title=Sx', 'document.title="Antigravity"')
        modified = True

    if modified:
        with open(js_file, "w", encoding="utf-8") as f:
            f.write(js)
        print(f"[Brand] Successfully patched {os.path.basename(js_file)}")

# 6. Marker file
with open(os.path.join(assets_dir, ".antigravity_branded"), "w") as f:
    f.write("branded\n")

print("[Brand] Antigravity branding & vector splash screen applied cleanly.")
