"""מוריד קישור אחד לתיקייה, עם זיהוי אוטומטי של סוג הקישור.

שימוש: python3 fetch.py <url> <out_dir> [--audio]
  - Google Drive (קובץ/תיקייה ציבוריים) -> gdown
  - magnet / .torrent                     -> aria2c
  - קובץ ישיר (EXE, ZIP, PDF...)          -> aria2c / requests
  - כל השאר (יוטיוב ואלפי אתרים)          -> yt-dlp, ואם נכשל -> הורדה ישירה
"""
import glob, os, re, shutil, subprocess, sys, time, urllib.parse

import gdown, requests, yt_dlp

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/130.0 Safari/537.36")
COOKIES = os.environ.get("COOKIES_FILE") or None


def safe_name(n):
    n = re.sub(r'[\\/:*?"<>|\r\n]+', "_", n).strip(" .")
    return n[:180] or f"file_{int(time.time())}"


def files_in(folder):
    return [p for p in glob.glob(os.path.join(folder, "**", "*"), recursive=True)
            if os.path.isfile(p) and not p.endswith((".part", ".ytdl", ".aria2"))]


def is_gdrive(url):
    return re.search(r"(drive|docs)\.google\.com|drive\.usercontent\.google\.com", url)


def dl_gdrive(url, out):
    m = re.search(r"/folders/([\w-]+)", url)
    if m:
        gdown.download_folder(id=m.group(1), output=out, quiet=False, use_cookies=False)
        return
    m = re.search(r"/d/([\w-]+)", url) or re.search(r"[?&]id=([\w-]+)", url)
    if not m:
        raise ValueError("לא זוהה מזהה קובץ בקישור הדרייב")
    gdown.download(id=m.group(1), output=out + "/", quiet=False, use_cookies=False)


def filename_from_response(r, url):
    cd = r.headers.get("content-disposition", "")
    m = re.search(r"filename\*\s*=\s*[^']*''([^;]+)", cd, re.I) or \
        re.search(r'filename\s*=\s*"?([^";]+)"?', cd, re.I)
    if m:
        return safe_name(urllib.parse.unquote(m.group(1)))
    path = urllib.parse.urlparse(r.url or url).path
    return safe_name(urllib.parse.unquote(os.path.basename(path)))


def probe(url):
    """מחזיר (האם זה קובץ ישיר, שם הקובץ)."""
    try:
        r = requests.get(url, headers={"User-Agent": UA}, stream=True,
                         allow_redirects=True, timeout=20)
        ctype = r.headers.get("content-type", "").lower()
        attach = "attachment" in r.headers.get("content-disposition", "").lower()
        name = filename_from_response(r, url)
        r.close()
        return ("text/html" not in ctype) or attach, name
    except Exception:
        return False, None


def dl_direct(url, out, name=None):
    name = name or f"file_{int(time.time())}"
    if shutil.which("aria2c"):
        res = subprocess.run(["aria2c", "-x16", "-s16", "-k1M", "--summary-interval=30",
                              "--console-log-level=warn", f"--user-agent={UA}",
                              "--allow-overwrite=true", "-d", out, "-o", name, url])
        if res.returncode == 0:
            return
    with requests.get(url, headers={"User-Agent": UA}, stream=True, timeout=60) as r:
        r.raise_for_status()
        with open(os.path.join(out, name), "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)


def dl_magnet(url, out):
    subprocess.run(["aria2c", "--seed-time=0", "--summary-interval=30",
                    "--console-log-level=warn", "-d", out, url], check=True)


def dl_ytdlp(url, out, audio=False):
    opts = {
        "outtmpl": os.path.join(out, "%(title).150B [%(id)s].%(ext)s"),
        "windowsfilenames": True, "noplaylist": False, "ignoreerrors": "only_download",
        "concurrent_fragment_downloads": 8, "retries": 10, "fragment_retries": 10,
        "noprogress": True, "no_warnings": True,
    }
    if COOKIES:
        opts["cookiefile"] = COOKIES
    if audio:
        opts.update({"format": "bestaudio/best",
                     "postprocessors": [{"key": "FFmpegExtractAudio",
                                         "preferredcodec": "mp3", "preferredquality": "320"}]})
    else:
        opts.update({"format": "bv*+ba/b", "merge_output_format": "mp4"})
    with yt_dlp.YoutubeDL(opts) as y:
        return y.download([url])


def fetch(url, out, audio=False):
    os.makedirs(out, exist_ok=True)
    if url.startswith("magnet:") or url.split("?")[0].endswith(".torrent"):
        print("🧲 טורנט"); dl_magnet(url, out); return
    if is_gdrive(url):
        print("📁 קישור דרייב"); dl_gdrive(url, out); return
    direct, name = (False, None) if audio else probe(url)
    if direct:
        print(f"📦 קובץ ישיר: {name}"); dl_direct(url, out, name); return
    print("🎬 וידאו/אודיו (yt-dlp)")
    try:
        ok = dl_ytdlp(url, out, audio) == 0
    except Exception as e:
        print("yt-dlp:", e); ok = False
    if not ok and not files_in(out) and not audio:
        print("לא נמצא וידאו, מנסה הורדה ישירה של הקובץ")
        dl_direct(url, out, name)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    url, out = sys.argv[1], sys.argv[2]
    fetch(url, out, audio="--audio" in sys.argv[3:])
    if not files_in(out):
        sys.exit("❌ לא הורד שום קובץ. ייתכן שהקישור פרטי, דורש התחברות, או לא נתמך.")
