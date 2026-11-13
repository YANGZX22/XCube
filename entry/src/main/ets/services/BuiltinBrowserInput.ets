// Fixed application scripts only: the model supplies text, never JavaScript or a DOM selector.
// No page/field contents leave the WebView; the bridge returns a small status enum.
const FOCUSED_EDITOR: string = `
const findEditor = () => {
  let doc = document;
  let element = doc.activeElement;
  for (let depth = 0; element && depth < 32; depth++) {
    if (element.shadowRoot && element.shadowRoot.activeElement) {
      element = element.shadowRoot.activeElement;
      continue;
    }
    if (element.tagName === 'IFRAME' || element.tagName === 'FRAME') {
      try {
        const child = element.contentDocument;
        if (!child) return { status: 'opaque' };
        doc = child;
        element = doc.activeElement;
        continue;
      } catch (_) { return { status: 'opaque' }; }
    }
    const field = element.tagName === 'TEXTAREA' ||
      (element.tagName === 'INPUT' && ['text', 'search', 'url', 'tel', 'email', 'password', 'number'].includes(element.type));
    if ((field || element.isContentEditable) && !element.disabled && !element.readOnly &&
      !element.matches(':disabled') && element.getClientRects().length > 0) {
      return { status: 'editable', doc, element, field };
    }
    // A closed shadow root does not expose its focused editor to page JavaScript.
    return { status: element.tagName.includes('-') ? 'opaque' : 'none' };
  }
  return { status: 'none' };
};
const editor = findEditor();
`

export const BROWSER_FOCUSED_EDITOR_SCRIPT: string = `(() => { ${FOCUSED_EDITOR} return editor.status; })()`

export function buildBrowserInsertTextScript(text: string, expiresAt: number): string {
  return `(() => {
    const expiresAt = ${expiresAt};
    if (Date.now() > expiresAt) return 'expired';
    ${FOCUSED_EDITOR}
    if (editor.status !== 'editable') return editor.status;
    const text = ${JSON.stringify(text)};
    const { doc, element, field } = editor;
    if (text === '') return 'inserted';
    if (!field) {
      // Chromium's editing command preserves the caret/selection and emits an input event.
      return doc.execCommand('insertText', false, text) ? 'inserted' : 'unconfirmed';
    }
    const before = element.value;
    const start = element.selectionStart === null ? before.length : element.selectionStart;
    const end = element.selectionEnd === null ? start : element.selectionEnd;
    const next = before.slice(0, start) + text + before.slice(end);
    if (element.maxLength >= 0 && next.length > element.maxLength) return 'too_long';
    const view = doc.defaultView;
    const event = new view.InputEvent('beforeinput', {
      data: text, inputType: 'insertText', bubbles: true, composed: true, cancelable: true
    });
    if (!element.dispatchEvent(event)) return 'rejected';
    if (Date.now() > expiresAt) return 'expired';
    if (!element.isConnected || findEditor().element !== element || element.value !== before) return 'changed';
    // Use the native setter so controlled inputs (for example React) observe a real value change.
    const prototype = element.tagName === 'TEXTAREA' ? view.HTMLTextAreaElement.prototype : view.HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, 'value').set;
    setter.call(element, next);
    try { element.setSelectionRange(start + text.length, start + text.length); } catch (_) {}
    element.dispatchEvent(new view.InputEvent('input', {
      data: text, inputType: 'insertText', bubbles: true, composed: true
    }));
    return element.value === next ? 'inserted' : 'unconfirmed';
  })()`
}

export function parseBrowserInputStatus(raw: string): string {
  let status = raw.trim()
  if (status.startsWith('"')) {
    status = JSON.parse(status) as string
  }
  if (!['editable', 'none', 'opaque', 'inserted', 'expired', 'too_long', 'rejected', 'changed', 'unconfirmed'].includes(status)) {
    throw new Error('网页输入状态无效，请重新截图确认')
  }
  return status
}
