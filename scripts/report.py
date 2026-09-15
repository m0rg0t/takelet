#!/usr/bin/env python3
"""Create a local, self-contained evidence report. No uploads or third-party resources."""
import base64
import html
import json
from pathlib import Path
import sys

manifest_path, result_dir, output = map(Path, sys.argv[1:4])
manifest = json.loads(manifest_path.read_text())
analysis = json.loads((result_dir / 'analysis.json').read_text())
checked = json.loads((result_dir / 'validated.json').read_text())
metrics = json.loads((result_dir / 'metrics.json').read_text())

def esc(value):
    return html.escape(str(value), quote=True)

cards = []
for frame in manifest['frames']:
    if frame['id'] not in manifest['selectedFrameIDs']:
        continue
    content = base64.b64encode((manifest_path.parent / frame['file']).read_bytes()).decode()
    cards.append(f'<figure id="{esc(frame["id"])}"><a href="#timeline"><img loading="lazy" src="data:image/jpeg;base64,{content}" alt="Recording frame {esc(frame["id"])}"></a><figcaption>{esc(frame["id"])} · {frame["time"]:.2f} s</figcaption></figure>')

rows = []
for item in checked:
    s = item['suggestion']
    status = 'Можно рассмотреть вырезку' if item['eligibleForReview'] else {'keep': 'Сохранить', 'uncertain': 'Недостаточно данных', 'cut': 'Вырезка отклонена'}.get(s['decision'], 'Ошибка')
    links = ' '.join(f'<a href="#{esc(e)}">{esc(e)}</a>' for e in s['evidence'])
    issues = ('<p class="issue">' + esc('; '.join(item['issues'])) + '</p>') if item['issues'] else ''
    rows.append(f'<tr><td>{s["start"]:.2f}–{s["end"]:.2f}</td><td><b>{status}</b><p>{esc(s["reason"])}</p>{issues}</td><td>{links}</td></tr>')

document = '''<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Takelet · Проверка анализа видео</title><style>
:root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#10151d;color:#edf2fb}body{max-width:1160px;margin:auto;padding:48px 24px}h1{font-size:34px;line-height:1.15;margin:16px 0}h2{margin-top:36px}.eyebrow{color:#8ebeff;letter-spacing:.12em;font-size:12px;text-transform:uppercase}.intro{font-size:18px;line-height:1.6;max-width:850px}.meta{display:flex;gap:12px;flex-wrap:wrap}.meta span,.note{background:#1d2735;border:1px solid #354359;border-radius:10px;padding:12px 16px}.note{margin:24px 0;line-height:1.6}table{width:100%;border-collapse:collapse}td,th{padding:16px;text-align:left;vertical-align:top;border-bottom:1px solid #354359}td:first-child{white-space:nowrap}p{line-height:1.5}a{color:#9cc7ff}td p{margin:8px 0 0}.issue{color:#ffc48e}.frames{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}figure{margin:0;background:#1d2735;border-radius:10px;overflow:hidden;scroll-margin-top:16px}img{width:100%;display:block}figcaption{padding:12px;color:#bdcce0}footer{margin-top:36px;color:#a2b3c8;font-size:13px}
</style><div class="eyebrow">Takelet · Прототип анализа</div><h1>Что видно на записи</h1>'''
document += f'<p class="intro">{esc(analysis["summary"])}</p><div class="meta"><span>{manifest["duration"]:.2f} с записи</span><span>{metrics["frameCount"]} кадров в запросе</span><span>{esc(metrics["model"])}</span><span>{metrics["elapsedSeconds"]:.1f} с анализа</span></div>'
document += f'<div class="note">Это результат одного запроса через Codex с авторизацией ChatGPT. Предложения не применены к видео. Статус аудио: <b>{esc(manifest["audioStatus"])}</b>. Нераспознанное аудио защищает всю запись. Кадры с интервалом 0,5 с не доказывают отсутствие коротких действий между ними.</div>'
document += '<h2 id="timeline">Наблюдения и проверка интервалов</h2><table><thead><tr><th>Время, с</th><th>Решение и причина</th><th>Кадры</th></tr></thead><tbody>' + ''.join(rows) + '</tbody></table><h2>Переданные кадры</h2><div class="frames">' + ''.join(cards) + '</div>'
document += f'<footer>Исходный файл: {esc(Path(manifest["source"]).name)}. Локальный отчёт, без внешних ресурсов. Версия протокола: Codex CLI 0.153.4.</footer></html>'
output.write_text(document)
print(output.resolve())
