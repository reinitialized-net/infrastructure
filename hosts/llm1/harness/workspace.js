// Local workspace: IndexedDB keeps attachments and conversations across reloads.
(async () => {
  const open = indexedDB.open('strata-workspace', 1);
  open.onupgradeneeded = () => open.result.createObjectStore('chats', {keyPath: 'id'});
  const db = await new Promise((resolve, reject) => { open.onsuccess = () => resolve(open.result); open.onerror = () => reject(open.error); });
  const transact = (mode, operation) => new Promise((resolve, reject) => {
    const tx = db.transaction('chats', mode), req = operation(tx.objectStore('chats'));
    tx.oncomplete = () => resolve(req.result); tx.onerror = () => reject(tx.error); tx.onabort = () => reject(tx.error);
  });
  const activeId = sessionStorage.getItem('strata.activeChat');
  const saved = activeId ? [] : await transact('readonly', s => s.getAll());
  let id = activeId || saved.sort((a,b)=>b.updated-a.updated)[0]?.id || crypto.randomUUID();
  let project = '', instructions = '';
  const remember = () => sessionStorage.setItem('strata.activeChat', id);
  remember();
  const previous = await transact('readonly', s => s.get(id));
  if (previous) { messages = previous.messages; project = previous.project; instructions = previous.instructions; renderChat(); }
  let pending = Promise.resolve();
  saveChat = () => {
    const chat = structuredClone({id, project, instructions, messages, updated: Date.now(), title: messages.find(m => m.role === 'user')?.text.slice(0, 90) || 'New chat'});
    pending = pending.catch(() => {}).then(() => transact('readwrite', s => s.put(chat)));
    pending.catch(() => toast('error', 'Chat could not be saved', 'Browser storage is full or unavailable. Export your conversation before closing this page.', 10000));
    return pending;
  };
  if (!previous && messages.length) await saveChat(); // migrate the existing chat without deleting it
  const originalApiMessages = apiMessages;
  apiMessages = () => {
    const result = originalApiMessages();
    if (instructions.trim()) result.unshift({role: 'system', content: instructions});
    return result;
  };
  const button = (label, action) => { const b = document.createElement('button'); b.type = 'button'; b.className = 'st-btn st-btn--secondary'; b.textContent = label; b.onclick = action; return b; };
  const idle = () => { if (!busy) return true; toast('warn', 'Still writing', 'Stop the answer first.'); return false; };
  const dialog = (title) => {
    const d = document.createElement('dialog'); d.className = 'workspace-dialog';
    const heading = document.createElement('h2'); heading.textContent = title;
    d.append(heading, button('Close', () => d.close()));
    d.addEventListener('close', () => d.remove()); document.body.append(d); d.showModal(); return d;
  };
  const download = (name, content, type = 'text/plain') => {
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([content], {type})); a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  };
  const bar = document.createElement('div'); bar.className = 'workspace-bar';
  $('view-chat').prepend(bar);
  bar.append(button('Chats & projects', async () => {
    if (!idle()) return;
    await saveChat();
    const d = dialog('Chats & projects');
    const note = document.createElement('p'); note.textContent = 'Saved in this browser. Export a backup before clearing browser data. Projects group chats; instructions apply to this chat.';
    const search = document.createElement('input'); search.className = 'st-input'; search.placeholder = 'Search chats, content, or project'; search.setAttribute('aria-label', search.placeholder);
    const list = document.createElement('div'); d.append(note, search, list);
    const chats = await transact('readonly', s => s.getAll());
    const render = () => {
      list.replaceChildren();
      for (const c of chats.sort((a,b) => b.updated-a.updated).filter(c => `${c.title} ${c.project} ${c.messages.map(m=>m.text).join(' ')}`.toLowerCase().includes(search.value.toLowerCase()))) {
        const row = document.createElement('div'); row.className = 'workspace-row';
        row.append(button(`${c.project ? c.project + ' / ' : ''}${c.title}`, async () => {
          if (!idle()) return;
          await saveChat(); id = c.id; project = c.project; instructions = c.instructions; messages = structuredClone(c.messages); attachments = []; remember(); renderAttachments(); renderChat(); d.close();
        }), button('Delete', async () => {
          if (!confirm('Delete this saved conversation?')) return;
          await transact('readwrite', s => s.delete(c.id)); chats.splice(chats.indexOf(c), 1);
          if (c.id === id) { id = crypto.randomUUID(); messages = []; project = ''; instructions = ''; remember(); renderChat(); }
          render();
        })); list.append(row);
      }
    }; search.oninput = render; render();
  }), button('Instructions', () => {
    if (!idle()) return;
    const d = dialog('Chat instructions');
    const p = document.createElement('input'); p.className = 'st-input'; p.placeholder = 'Project name'; p.setAttribute('aria-label', 'Project name'); p.value = project;
    const text = document.createElement('textarea'); text.className = 'st-input'; text.rows = 8; text.placeholder = 'Preferences and context for this chat'; text.setAttribute('aria-label', text.placeholder); text.value = instructions;
    d.append(p, text, button('Save instructions', async () => { project = p.value.slice(0,120); instructions = text.value.slice(0,12000); await saveChat(); d.close(); }));
  }), button('Backup chat', () => download('strata-chat.json', JSON.stringify({version: 1, project, instructions, messages}, null, 2), 'application/json')),
  button('Import chat', () => {
    if (!idle()) return;
    const f = document.createElement('input'); f.type = 'file'; f.accept = '.json';
    f.onchange = async () => {
      try {
        if (!f.files[0] || f.files[0].size > 20e6) throw Error('Choose a chat backup under 20 MB.');
        const c = JSON.parse(await f.files[0].text());
        if (c.version !== 1 || !Array.isArray(c.messages) || !c.messages.every(m => ['user','assistant'].includes(m.role) && typeof m.text === 'string')) throw Error('Invalid Strata chat backup.');
        // Imports are data only. Ignore tool events and arbitrary object fields.
        const imported = c.messages.map(m => ({role:m.role, text:m.text, time:Number(m.time)||Date.now(), files:(Array.isArray(m.files)?m.files:[]).filter(f=>typeof f.name==='string' && typeof f.text==='string').map(f=>({name:f.name,text:f.text,kind:'file'}))}));
        await saveChat(); id = crypto.randomUUID(); project = typeof c.project==='string'?c.project:''; instructions=typeof c.instructions==='string'?c.instructions:''; messages=imported; remember(); await saveChat(); renderChat();
      } catch(e) { toast('error','Import failed',String(e.message),8000); }
    }; f.click();
  }));
  $('new-btn').onclick = async () => {
    if (!idle()) return; await saveChat(); id = crypto.randomUUID(); remember(); messages = []; attachments = []; renderAttachments(); renderChat(); await saveChat();
    toast('info', 'New chat', 'Previous chats remain in Chats & projects. Current instructions are retained.');
  };
  // Branch before editing or retrying, preserving the original conversation.
  const baseMsgEl = msgEl;
  msgEl = (m, i) => {
    const el = baseMsgEl(m, i);
    el.append(button(m.role === 'user' ? 'Edit & branch' : 'Retry in new branch', async () => {
      if (!idle()) return;
      const userIndex = m.role === 'user' ? i : messages.slice(0,i).findLastIndex(x=>x.role==='user');
      if(userIndex < 0) return;
      await saveChat(); const source = structuredClone(messages[userIndex]); messages = structuredClone(messages.slice(0,userIndex)); id = crypto.randomUUID(); remember();
      $('input').value = source.text; attachments = [...(source.files||[]), ...(source.images||[])]; renderAttachments(); renderChat(); autosize(); await saveChat();
      if (m.role !== 'user') send(); else $('input').focus();
    })); return el;
  };
  const baseCodeBlock = codeBlock;
  codeBlock = (lang, code) => baseCodeBlock(lang, code).replace('</div><pre>', `<button class="st-btn" data-artifact-download>Download</button>${/^(html|svg)$/i.test(lang)?'<button class="st-btn" data-artifact-preview>Preview</button>':''}</div><pre>`);
  $('chat').addEventListener('click', e => {
    const b = e.target.closest('[data-artifact-download], [data-artifact-preview]'); if (!b) return;
    const block = b.closest('.st-code'), code = block.querySelector('code').textContent, lang = block.querySelector('.st-code__head span').textContent;
    if (b.hasAttribute('data-artifact-download')) { download('artifact.' + ({python:'py',javascript:'js',typescript:'ts',markdown:'md'}[lang] || (/^[a-z0-9]{1,12}$/i.test(lang)?lang:'txt')),code); return; }
    const d = dialog('Artifact preview');
    const frame = document.createElement('iframe'); frame.title='Artifact preview'; frame.setAttribute('sandbox',''); frame.referrerPolicy='no-referrer';
    frame.srcdoc = `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; form-action 'none'; base-uri 'none'">` + code;
    d.append(frame); // No scripts, network, forms, or parent-origin access.
  });
  renderChat();
})().catch(e => toast('error', 'Workspace unavailable', 'Browser storage could not be opened. Export this chat before leaving. ' + e.message, 10000));
// Documents enter the same attachment path as text, after isolated extraction.
let extractingDocuments = 0;
const workspaceSend = send;
send = () => {
  if (extractingDocuments) { toast('info', 'Reading attachments', 'Wait for document extraction before sending.'); return; }
  return workspaceSend();
};
const textAddFiles = addFiles;
addFiles = async (files) => {
  for (const f of files) {
    if (!/\.(pdf|docx|xlsx)$/i.test(f.name)) { textAddFiles([f]); continue; }
    if (f.size > 8_000_000) { toast('warn','Document too large','Use documents under 8 MB.'); continue; }
    const targetChat = sessionStorage.getItem('strata.activeChat');
    extractingDocuments++;
    try {
      toast('info','Reading document',f.name);
      const bytes = new Uint8Array(await f.arrayBuffer());
      let binary = ''; for (let i=0;i<bytes.length;i+=8192) binary += String.fromCharCode(...bytes.subarray(i,i+8192));
      const r = await fetch('workspace/extract',{method:'POST',headers:headers(true),body:JSON.stringify({name:f.name,data:btoa(binary)})});
      const result = await r.json(); if(!r.ok) throw Error(typeof result.error==='string'?result.error:result.error?.message||'Extraction failed');
      if (!result.text.trim()) throw Error('No readable text found. Scanned documents need OCR, which is not enabled.');
      if (targetChat !== sessionStorage.getItem('strata.activeChat')) throw Error('The active chat changed. Attach the document again in the intended chat.');
      attachments.push({kind:'file',name:f.name,text:result.text}); renderAttachments();
    } catch(e) { toast('error','Document could not be read',e.message,10000); }
    finally { extractingDocuments--; }
  }
};
// Artifact responses are structured MCP data, never trusted HTML.
const workspaceAnswerHtml = answerHtml;
answerHtml = (m) => {
  let html = workspaceAnswerHtml(m);
  for (const t of m.tools || []) {
    if (t.name !== 'analysis__python' || !t.result) continue;
    try {
      const result = JSON.parse(t.result);
      for (const a of result.artifacts || []) {
        if (/^\/workspace\/artifacts\/[0-9a-f]{32}$/.test(a.url) && typeof a.name === 'string')
          html += `<p><button class="st-btn st-btn--secondary" data-workspace-url="${a.url}" data-workspace-name="${esc(a.name)}">Download ${esc(a.name)}</button></p>`;
      }
    } catch (_) { /* normal tool errors stay visible in the tool card */ }
  }
  return html;
};
$('chat').addEventListener('click', async e => {
  const b = e.target.closest('[data-workspace-url]'); if (!b) return;
  try {
    const r = await fetch(b.dataset.workspaceUrl, {headers:headers()});
    if (!r.ok) throw Error(r.status===404?'This download expired. Ask the model to recreate it.':`Download failed (${r.status})`);
    const a = document.createElement('a'); a.href=URL.createObjectURL(await r.blob()); a.download=b.dataset.workspaceName; a.click(); setTimeout(()=>URL.revokeObjectURL(a.href),1000);
  } catch(e) { toast('error','Download unavailable',e.message); }
});
