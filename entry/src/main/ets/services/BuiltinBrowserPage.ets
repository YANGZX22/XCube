export class BrowserPageText {
  url: string = ''
  title: string = ''
  text: string = ''
  start: number = 0
  next_start: number = 0
  has_more: boolean = false
  limited: boolean = false
}

// Fixed, read-only extraction of rendered document text; no model-provided selectors or JavaScript.
export function buildBrowserPageTextScript(start: number, maxChars: number, expiresAt: number): string {
  return `(() => {
    if (Date.now() > ${expiresAt}) throw new Error('page_read_expired');
    const start = ${start}, count = ${maxChars};
    const root = document.querySelector('main') || document.querySelector('article') || document.body;
    const walker = document.createTreeWalker(root || document, NodeFilter.SHOW_TEXT);
    const skip = 'script,style,noscript,template,input,textarea,select,[contenteditable]:not([contenteditable="false"]),[hidden],[aria-hidden="true"]';
    let text = '', visited = 0, node = null, limited = false;
    while ((node = walker.nextNode())) {
      if (++visited > 30000 || text.length >= 516001) { limited = true; break; }
      const parent = node.parentElement;
      if (!parent || parent.closest(skip) || !parent.getClientRects().length) continue;
      const style = getComputedStyle(parent);
      if (style.visibility === 'hidden' || style.visibility === 'collapse' || style.display === 'none') continue;
      const value = node.textContent.replace(/\\s+/g, ' ').trim();
      if (value) text = (text + value + '\\n').slice(0, Math.min(516001, start + count + 1));
      if (text.length > start + count) break;
    }
    const content = text.slice(start, start + count);
    return JSON.stringify({ url: location.href, title: document.title, text: content, start,
      next_start: start + content.length, has_more: text.length > start + count,
      limited: limited || start + content.length >= 500000 });
  })()`
}

export function parseBrowserPageText(raw: string, start: number, maxChars: number): BrowserPageText {
  let parsed: Object = JSON.parse(raw) as Object
  if (typeof parsed === 'string') parsed = JSON.parse(parsed) as Object
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('网页正文返回无效')
  const data = parsed as Record<string, Object>
  if (typeof data['url'] !== 'string' || typeof data['title'] !== 'string' || typeof data['text'] !== 'string' ||
    data['start'] !== start || typeof data['has_more'] !== 'boolean' || typeof data['limited'] !== 'boolean') {
    throw new Error('网页正文返回无效')
  }
  const result = new BrowserPageText()
  result.url = (data['url'] as string).slice(0, 8192)
  result.title = (data['title'] as string).slice(0, 1000)
  result.text = (data['text'] as string).slice(0, maxChars)
  result.start = start
  result.next_start = start + result.text.length
  result.has_more = data['has_more'] === true && result.text.length > 0 && result.next_start <= 500000
  result.limited = data['limited'] === true
  return result
}

// Same-document fragment navigation must not reload the document or synthesize a guessed anchor.
export function buildBrowserFragmentScript(url: string, expiresAt: number): string {
  return `(() => {
    if (Date.now() > ${expiresAt}) return 'expired';
    const target = new URL(${JSON.stringify(url)}), current = new URL(location.href);
    if (target.origin !== current.origin || target.pathname !== current.pathname || target.search !== current.search) return 'different_document';
    let id = target.hash.slice(1);
    try { id = decodeURIComponent(id); } catch (_) {}
    const element = id ? (document.getElementById(id) || document.getElementsByName(id)[0]) : null;
    if (location.hash !== target.hash) location.hash = target.hash;
    if (!id) { window.scrollTo(0, 0); return 'moved'; }
    if (!element) return 'missing';
    element.scrollIntoView({ block: 'start', behavior: 'instant' });
    return 'moved';
  })()`
}
