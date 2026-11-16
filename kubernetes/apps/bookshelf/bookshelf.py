"""The bookshelf: a password-gated page of EPUBs, plain enough for an old iPad.

Safari on iOS 9 runs no modern JavaScript, so everything here is server-rendered
HTML behind one password form, the session is a cookie that lasts a year, and
books go out as application/epub+zip so Safari offers "Open in iBooks".

iOS 9 also trusts only the certificate authorities of 2015, older than the roots
Let's Encrypt chains to. /trust.mobileconfig, open to anyone, is a profile of
three current roots (ISRG Root X1 and X2, USERTrust RSA) for such a device to
install once; the login page links to it.

Books arrive from `shelve` on the Mac (dotfiles configs/bookshelf): PUT
/books/<name>.epub with the password as HTTP Basic auth, in chunks, because
Traefik gives a whole request 60 seconds and a big illustrated book would not
make it up a home connection in one piece.

They also arrive from a browser: the shelf page takes EPUBs dropped on it or
chosen, and a small script sends them as the same chunked PUTs, signed in by the
session cookie. It shows only where fetch exists, so iOS 9, which can pick
nothing but photos anyway, keeps the plain shelf; and it is ES5, so that Safari
still parses the page.

Usage: bookshelf.py [--port N] folder      (password in $BOOKSHELF_PASSWORD)
"""
import argparse
import base64
import contextlib
import email.utils
import functools
import hashlib
import hmac
import html
import http.cookies
import os
import shutil
import threading
import time
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NS = {
    "c": "urn:oasis:names:tc:opendocument:xmlns:container",
    "dc": "http://purl.org/dc/elements/1.1/",
}
COOKIE = "shelf"
YEAR = 365 * 24 * 3600
MAX_BOOK = 1 << 30  # a whole book
MAX_CHUNK = 64 << 20  # one PUT's body
TRUST_PROFILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "trust.mobileconfig")

PASSWORD = os.environ.get("BOOKSHELF_PASSWORD", "")
# The cookie proves the password without carrying it, and changes with it, so
# a new password signs every device out.
SESSION = hmac.new(PASSWORD.encode(), b"bookshelf session", hashlib.sha256).hexdigest()
FOLDER = ""  # set in main()

PAGE = """<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Bookshelf</title>
<link rel="icon" href="data:,">
<style>
  body {{ margin: 0; background: #f7f3ea; color: #2b2622; font-family: Georgia, serif; }}
  main {{ max-width: 620px; margin: 0 auto; padding: 40px 20px 64px; }}
  h1 {{ font-weight: normal; font-size: 32px; margin: 0 0 8px; }}
  p {{ color: #7a7066; font-size: 17px; line-height: 1.4; margin: 0 0 28px; }}
  p.error {{ color: #a1432f; }}
  a {{ display: block; padding: 18px 6px; border-top: 1px solid #e2dacb; color: inherit; text-decoration: none; }}
  a:last-child {{ border-bottom: 1px solid #e2dacb; }}
  a:active {{ background: #ebe3d4; }}
  .title {{ font-size: 21px; line-height: 1.3; }}
  .author {{ font-size: 16px; color: #7a7066; margin-top: 4px; }}
  input, button {{ font-family: Georgia, serif; font-size: 21px; border-radius: 0; -webkit-appearance: none; }}
  input {{ display: block; width: 100%; box-sizing: border-box; padding: 12px; margin: 0 0 16px;
           border: 1px solid #d6cdbc; background: #fffdf8; color: inherit; }}
  button {{ padding: 12px 28px; border: 0; background: #2b2622; color: #f7f3ea; }}
  p.note {{ font-size: 15px; margin: 36px 0 0; }}
  p.note a {{ display: inline; padding: 0; border: 0; text-decoration: underline; }}
  .add {{ margin: 0 0 28px; padding: 16px 18px; border: 1px dashed #d6cdbc; }}
  .add p {{ margin: 0; }}
  .add label {{ text-decoration: underline; cursor: pointer; }}
  .add input {{ display: none; }}
  body.dropping .add {{ border-color: #2b2622; background: #fffdf8; }}
  #progress {{ list-style: none; margin: 0; padding: 0; font-size: 16px; color: #7a7066; }}
  #progress li {{ margin-top: 8px; overflow-wrap: break-word; }}
</style>
</head>
<body ontouchstart="">
<main>
<h1>Bookshelf</h1>
{body}
</main>
{script}
</body></html>
"""

ADD = """<div class="add" id="add" style="display: none">
<p>Add books: drop EPUBs on this page, or <label>choose them<input type="file" id="files"
accept=".epub,application/epub+zip" multiple></label>.</p>
<ul id="progress"></ul>
</div>"""

# ES5 throughout: iOS 9's Safari must still parse it, even though it bails out
# at the fetch check and never shows the drop box.
UPLOAD_SCRIPT = """<script>
(function () {
  if (!window.fetch || !window.Promise || !window.Blob || !Blob.prototype.slice) return;
  var CHUNK = 8 * 1024 * 1024;
  var add = document.getElementById("add");
  var input = document.getElementById("files");
  var list = document.getElementById("progress");
  add.style.display = "";

  function row(name) {
    var li = document.createElement("li");
    list.appendChild(li);
    return function (status) { li.textContent = name + ": " + status; };
  }

  function put(file, offset, last) {
    var url = "/books/" + encodeURIComponent(file.name) + "?offset=" + offset + (last ? "&final=1" : "");
    return fetch(url, { method: "PUT", body: file.slice(offset, offset + CHUNK), credentials: "same-origin" })
      .then(function (response) { return response.status; });
  }

  // Resolves with what to tell the reader; rejects only when a retry could help.
  function send(file, show) {
    var offset = 0;
    function next() {
      var last = offset + CHUNK >= file.size;
      return put(file, offset, last).then(function (status) {
        if (status === 409 && offset === 0) return "already on the shelf";
        if (status === 422) return "not an EPUB";
        if (status === 400) return "the shelf refused that file name";
        if (status === 413) return "too big for the shelf";
        if (status === 401) return "signed out; reload the page and sign in";
        if (status !== 201 && status !== 204) throw new Error("the shelf answered " + status);
        if (last) return "added";
        offset += CHUNK;
        show(Math.floor(offset * 100 / file.size) + "%");
        return next();
      });
    }
    return next();
  }

  // A failure starts the book over from its first byte, up to three times.
  function shelve(file, show, attempt) {
    return send(file, show).catch(function (error) {
      if (attempt >= 3) return "failed (" + error.message + ")";
      show("retrying");
      return shelve(file, show, attempt + 1);
    });
  }

  // Swap in the fresh list of books instead of reloading, so the messages stay.
  function refreshShelf() {
    return fetch("/", { credentials: "same-origin" })
      .then(function (response) { return response.text(); })
      .then(function (text) {
        var fresh = new DOMParser().parseFromString(text, "text/html").querySelector("main");
        var main = document.querySelector("main");
        Array.prototype.forEach.call(main.querySelectorAll("main > a"), function (a) { main.removeChild(a); });
        Array.prototype.forEach.call(fresh.querySelectorAll("main > a"), function (a) {
          main.appendChild(document.importNode(a, true));
        });
        main.querySelector("main > p").textContent = fresh.querySelector("main > p").textContent;
      })
      .catch(function () { list.appendChild(document.createTextNode("Reload the page to see the new books.")); });
  }

  function shelveAll(files) {
    var added = 0;
    var queue = Promise.resolve();
    Array.prototype.forEach.call(files, function (file) {
      var show = row(file.name);
      if (!/\\.epub$/i.test(file.name)) { show("skipped, not an .epub"); return; }
      show("waiting");
      queue = queue.then(function () {
        show("0%");
        return shelve(file, show, 1).then(function (outcome) {
          show(outcome);
          if (outcome === "added") added += 1;
        });
      });
    });
    queue.then(function () {
      if (added) return refreshShelf();
    });
  }

  input.addEventListener("change", function () {
    var files = Array.prototype.slice.call(input.files);
    input.value = "";
    shelveAll(files);
  });

  var depth = 0;
  document.addEventListener("dragenter", function (event) {
    event.preventDefault();
    depth += 1;
    document.body.className = "dropping";
  });
  document.addEventListener("dragleave", function () {
    depth -= 1;
    if (depth <= 0) { depth = 0; document.body.className = ""; }
  });
  document.addEventListener("dragover", function (event) { event.preventDefault(); });
  document.addEventListener("drop", function (event) {
    event.preventDefault();
    depth = 0;
    document.body.className = "";
    if (event.dataTransfer && event.dataTransfer.files.length) shelveAll(event.dataTransfer.files);
  });
})();
</script>"""

LOGIN = """<p{cls}>{message}</p>
<form method="post" action="/login">
<input type="password" name="password" autofocus>
<button type="submit">Open</button>
</form>
<p class="note">Did Safari warn about this site's certificate? Install the
<a href="/trust.mobileconfig">certificate profile</a> once, and it won't again.</p>"""

_guessing = threading.Lock()


def password_ok(candidate):
    """Whether candidate is the password. A wrong guess costs two seconds, one at a time."""
    if hmac.compare_digest(candidate.encode(), PASSWORD.encode()):
        return True
    with _guessing:
        time.sleep(2)
    return False


@functools.lru_cache(maxsize=1024)
def metadata(path, mtime):
    """(title, author) from the EPUB's package file; the filename if it can't be read.

    mtime is only there for the cache key, so a replaced file is read again.
    """
    title, author = os.path.splitext(os.path.basename(path))[0], ""
    with contextlib.suppress(Exception):
        with zipfile.ZipFile(path) as z:
            rootfile = ET.fromstring(z.read("META-INF/container.xml")).find(".//c:rootfile", NS)
            package = ET.fromstring(z.read(rootfile.get("full-path")))
            title = package.findtext(".//dc:title", "", NS).strip() or title
            author = package.findtext(".//dc:creator", "", NS).strip()
    return title, author


def shelf():
    """{filename: (path, mtime)} for the EPUBs on the shelf, newest first."""
    found = {}
    with contextlib.suppress(OSError):
        for entry in os.scandir(FOLDER):
            name = entry.name
            if name.lower().endswith(".epub") and not name.startswith(".") and entry.is_file():
                found[name] = (entry.path, entry.stat().st_mtime)
    return dict(sorted(found.items(), key=lambda item: item[1][1], reverse=True))


def valid_name(name):
    return (name.lower().endswith(".epub") and not name.startswith(".")
            and name == os.path.basename(name) and "\\" not in name and "\0" not in name
            and len(name.encode()) <= 240)


def is_epub(path):
    with contextlib.suppress(Exception), zipfile.ZipFile(path) as z:
        return "META-INF/container.xml" in z.namelist()
    return False


class Handler(BaseHTTPRequestHandler):
    server_version = "bookshelf"
    sys_version = ""

    def do_GET(self):
        self.respond(send_body=True)

    def do_HEAD(self):
        self.respond(send_body=False)

    def respond(self, send_body):
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if path == "/robots.txt":
            return self.send(b"User-agent: *\nDisallow: /\n", "text/plain; charset=utf-8", send_body)
        if path == "/trust.mobileconfig":
            with open(TRUST_PROFILE, "rb") as f:
                return self.send(f.read(), "application/x-apple-aspen-config", send_body)
        if not self.signed_in():
            if "Authorization" in self.headers:
                return self.send_error(401)  # a client with the wrong password, not a browser to redirect
            if path == "/":
                return self.send(self.page(self.login_form()), "text/html; charset=utf-8", send_body)
            return self.redirect("/")
        books = shelf()
        name = path.removeprefix("/books/") if path.startswith("/books/") else None
        if path == "/":
            self.send(self.page(self.shelf_body(books), UPLOAD_SCRIPT), "text/html; charset=utf-8", send_body)
        elif name in books:
            self.send_book(books[name][0], send_body)
        else:
            self.send_error(404)

    def do_POST(self):
        if urllib.parse.urlsplit(self.path).path != "/login":
            return self.send_error(404)
        length = int(self.headers.get("Content-Length") or 0)
        if not 0 <= length <= 4096:
            return self.send_error(413)
        form = urllib.parse.parse_qs(self.rfile.read(length).decode("utf-8", "replace"))
        if not password_ok(form.get("password", [""])[0]):
            return self.send(self.page(self.login_form(wrong=True)), "text/html; charset=utf-8", True, status=401)
        expires = email.utils.formatdate(time.time() + YEAR, usegmt=True)
        self.send_response(303)
        self.send_header("Location", "/")
        self.send_header("Set-Cookie", f"{COOKIE}={SESSION}; Max-Age={YEAR}; Expires={expires}; "
                                       "Path=/; HttpOnly; Secure; SameSite=Lax")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_PUT(self):
        """Upload a book: one body, or ?offset=N chunks with &final=1 on the last."""
        url = urllib.parse.urlsplit(self.path)
        path = urllib.parse.unquote(url.path)
        name = path.removeprefix("/books/")
        if not self.signed_in():
            return self.send_error(401)  # no WWW-Authenticate: browsers must never pop a prompt
        if not path.startswith("/books/") or not valid_name(name):
            return self.send_error(400, "Expected PUT /books/<name>.epub")
        query = urllib.parse.parse_qs(url.query)
        try:
            offset = int(query.get("offset", ["0"])[0])
            length = int(self.headers["Content-Length"])
        except (TypeError, ValueError):
            return self.send_error(411)
        final = "offset" not in query or "final" in query
        if offset < 0 or length < 0 or length > MAX_CHUNK or offset + length > MAX_BOOK:
            return self.send_error(413)
        target = os.path.join(FOLDER, name)
        partial = os.path.join(FOLDER, ".partial." + name)
        if os.path.exists(target):
            return self.send_error(409, "Already on the shelf")
        have = os.path.getsize(partial) if offset and os.path.exists(partial) else 0
        if offset != have:
            return self.send_error(409, f"Expected offset {have}")
        with open(partial, "ab" if offset else "wb") as f:
            remaining = length
            while remaining:
                chunk = self.rfile.read(min(remaining, 1 << 20))
                if not chunk:
                    return  # the client went away; its next offset will not match
                f.write(chunk)
                remaining -= len(chunk)
        if not final:
            return self.send_status(204)
        if not is_epub(partial):
            os.remove(partial)
            return self.send_error(422, "Not an EPUB")
        os.replace(partial, target)
        self.send_status(201)

    def signed_in(self):
        with contextlib.suppress(http.cookies.CookieError):
            jar = http.cookies.SimpleCookie(self.headers.get("Cookie", ""))
            if COOKIE in jar and hmac.compare_digest(jar[COOKIE].value, SESSION):
                return True
        scheme, _, credentials = self.headers.get("Authorization", "").partition(" ")
        if scheme.lower() == "basic":
            with contextlib.suppress(ValueError, UnicodeDecodeError):
                return password_ok(base64.b64decode(credentials).decode().partition(":")[2])
        return False

    def login_form(self, wrong=False):
        if wrong:
            return LOGIN.format(cls=' class="error"', message="That's not it. Try again.")
        return LOGIN.format(cls="", message="Enter the password to open the shelf.")

    def shelf_body(self, books):
        rows = []
        for name, (path, mtime) in books.items():
            title, author = metadata(path, mtime)
            byline = f'<div class="author">{html.escape(author)}</div>' if author else ""
            rows.append(
                f'<a href="/books/{urllib.parse.quote(name)}">'
                f'<div class="title">{html.escape(title)}</div>{byline}</a>'
            )
        hint = ("Tap a book, then tap Open in iBooks." if books
                else "No books yet. Add some from a computer: drop them on this page, or run shelve.")
        return f"<p>{hint}</p>\n{ADD}\n" + "\n".join(rows)

    def page(self, body, script=""):
        return PAGE.format(body=body, script=script).encode()

    def send(self, body, ctype, send_body, status=200):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def send_book(self, path, send_body):
        self.send_response(200)
        self.send_header("Content-Type", "application/epub+zip")
        self.send_header("Content-Length", str(os.path.getsize(path)))
        self.end_headers()
        if send_body:
            with open(path, "rb") as f, contextlib.suppress(BrokenPipeError, ConnectionResetError):
                shutil.copyfileobj(f, self.wfile)

    def send_status(self, status):
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def redirect(self, location):
        self.send_response(303)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def end_headers(self):
        self.send_header("X-Robots-Tag", "noindex, nofollow")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()

    def address_string(self):
        # Traefik is the peer; the reader is in X-Forwarded-For.
        forwarded = getattr(self, "headers", None) and self.headers.get("X-Forwarded-For", "")
        return (forwarded or "").split(",")[0].strip() or self.client_address[0]


def main():
    global FOLDER
    parser = argparse.ArgumentParser(description="Serve a folder of EPUBs to an old iPad, behind a password.")
    parser.add_argument("folder")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    if not PASSWORD:
        raise SystemExit("BOOKSHELF_PASSWORD is empty; refusing to serve the shelf without one")
    FOLDER = args.folder
    os.makedirs(FOLDER, exist_ok=True)
    print(f"Serving {FOLDER} on port {args.port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
