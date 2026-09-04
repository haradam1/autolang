import Foundation

/// Builds a self-contained HTML dashboard from the stats. Menus can't draw
/// charts, so "Open detailed stats…" writes this to a file and opens it in the
/// browser. No external assets — inline CSS, theme-aware, RTL-aware labels.
enum StatsReport {

    static func html(from d: Stats.Data, top: [(word: String, count: Int)]) -> String {
        let maxWord = max(top.first?.count ?? 1, 1)
        let maxDir = max(d.enToHe, d.heToEn, 1)

        let wordRows = top.isEmpty
            ? "<p class=\"empty\">No conversions recorded yet.</p>"
            : top.map { row in
                let pct = Int(Double(row.count) / Double(maxWord) * 100)
                return """
                <div class="row">
                  <div class="label" dir="auto">\(esc(row.word))</div>
                  <div class="track"><div class="bar" style="width:\(pct)%"></div></div>
                  <div class="num">\(row.count)</div>
                </div>
                """
            }.joined(separator: "\n")

        let enPct = Int(Double(d.enToHe) / Double(maxDir) * 100)
        let hePct = Int(Double(d.heToEn) / Double(maxDir) * 100)

        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>AutoLang — Statistics</title>
        <style>
          :root{
            --bg:#f7f7f9; --card:#fff; --ink:#1c1c22; --muted:#6a6a76;
            --line:#e6e6ec; --accent:#4f7cff; --accent2:#12b886;
          }
          @media (prefers-color-scheme: dark){
            :root{ --bg:#16161a; --card:#1f1f26; --ink:#ececf2; --muted:#9a9aa6;
                   --line:#2c2c36; --accent:#6b93ff; --accent2:#2fd39a; }
          }
          *{box-sizing:border-box}
          body{margin:0;padding:32px;background:var(--bg);color:var(--ink);
               font:15px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",Segoe UI,sans-serif}
          h1{font-size:22px;margin:0 0 4px} .sub{color:var(--muted);margin:0 0 24px}
          .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:14px;margin-bottom:26px}
          .tile{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px}
          .tile .k{font-size:28px;font-weight:650} .tile .t{color:var(--muted);font-size:13px}
          .card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:20px;margin-bottom:22px}
          .card h2{font-size:15px;margin:0 0 16px;font-weight:600}
          .row{display:grid;grid-template-columns:minmax(70px,150px) 1fr 44px;align-items:center;gap:12px;margin:8px 0}
          .label{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
          .num{text-align:right;color:var(--muted);font-variant-numeric:tabular-nums}
          .track{background:var(--line);border-radius:7px;height:14px;overflow:hidden}
          .bar{height:100%;background:var(--accent);border-radius:7px}
          .bar.g{background:var(--accent2)}
          .empty{color:var(--muted)}
          .foot{color:var(--muted);font-size:12px;margin-top:8px}
        </style></head><body>
          <h1>AutoLang Statistics</h1>
          <p class="sub">Layout conversions and corrections on this Mac · v\(esc(AppInfo.version))</p>

          <div class="grid">
            <div class="tile"><div class="k">\(d.total)</div><div class="t">Total conversions</div></div>
            <div class="tile"><div class="k">\(d.typoFixes)</div><div class="t">Typo fixes</div></div>
            <div class="tile"><div class="k">\(d.manualConverts)</div><div class="t">Manual (⌃⌥H)</div></div>
            <div class="tile"><div class="k">\(d.undos)</div><div class="t">Undos</div></div>
          </div>

          <div class="card">
            <h2>Direction</h2>
            <div class="row"><div class="label">EN → HE</div>
              <div class="track"><div class="bar" style="width:\(enPct)%"></div></div>
              <div class="num">\(d.enToHe)</div></div>
            <div class="row"><div class="label">HE → EN</div>
              <div class="track"><div class="bar g" style="width:\(hePct)%"></div></div>
              <div class="num">\(d.heToEn)</div></div>
          </div>

          <div class="card">
            <h2>Most converted words</h2>
            \(wordRows)
          </div>

          <p class="foot">All data is stored locally on your Mac.</p>
        </body></html>
        """
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
