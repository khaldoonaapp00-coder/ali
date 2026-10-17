const express = require('express');
const Database = require('better-sqlite3');
const path = require('path');

const app = express();
const PORT = 3000;
const db = new Database('database.db');

// إعداد قاعدة البيانات
db.exec(`
  CREATE TABLE IF NOT EXISTS conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
  CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER,
    role TEXT,
    content TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(conversation_id) REFERENCES conversations(id)
  );
`);

app.use(express.json());

// واجهة المستخدم (HTML مدمج)
app.get('/', (req, res) => {
  res.send(`
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<title>AI Pro</title>
<style>
  body { display: flex; height: 100vh; margin: 0; font-family: sans-serif; background: #212121; color: #ececec; }
  #sidebar { width: 250px; background: #171717; padding: 10px; overflow-y: auto; border-left: 1px solid #333; }
  .conv-item { padding: 10px; cursor: pointer; border-radius: 5px; margin-bottom: 5px; font-size: 14px;}
  .conv-item:hover { background: #2a2a2a; }
  #main { flex: 1; display: flex; flex-direction: column; }
  #chat { flex: 1; padding: 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 15px; }
  .msg { max-width: 80%; padding: 12px 16px; border-radius: 8px; line-height: 1.5; white-space: pre-wrap; }
  .user { background: #2f2f2f; align-self: flex-start; }
  .ai { background: transparent; align-self: flex-end; }
  #input-area { padding: 20px; background: #212121; }
  #prompt { width: 100%; padding: 15px; background: #2f2f2f; border: 1px solid #444; border-radius: 8px; color: white; resize: none; font-size: 16px; outline: none; }
  button { padding: 10px; background: #10a37f; color: white; border: none; border-radius: 5px; cursor: pointer; margin-bottom: 10px; width: 100%; }
</style>
</head>
<body>
<div id="sidebar">
  <button onclick="newConv()">+ محادثة جديدة</button>
  <div id="conv-list"></div>
</div>
<div id="main">
  <div id="chat"></div>
  <div id="input-area">
    <textarea id="prompt" rows="2" placeholder="اكتب رسالتك..." onkeydown="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();send()}"></textarea>
  </div>
</div>
<script>
  let currentConvId = null;
  let messages = [];

  async function loadConvs() {
    const res = await fetch('/api/conversations');
    const data = await res.json();
    const list = document.getElementById('conv-list');
    list.innerHTML = '';
    data.forEach(c => {
      const div = document.createElement('div');
      div.className = 'conv-item';
      div.innerText = c.title + ' (#' + c.id + ')';
      div.onclick = () => loadMessages(c.id);
      list.appendChild(div);
    });
  }

  async function newConv() {
    const res = await fetch('/api/conversations', { method: 'POST', headers: {'Content-Type':'application/json'} });
    const data = await res.json();
    currentConvId = data.id;
    messages = [];
    document.getElementById('chat').innerHTML = '';
    loadConvs();
  }

  async function loadMessages(id) {
    currentConvId = id;
    const res = await fetch('/api/conversations/' + id + '/messages');
    messages = await res.json();
    const chat = document.getElementById('chat');
    chat.innerHTML = '';
    messages.forEach(m => addBubble(m.role, m.content));
  }

  function addBubble(role, text) {
    const div = document.createElement('div');
    div.className = 'msg ' + role;
    div.innerText = text;
    document.getElementById('chat').appendChild(div);
    document.getElementById('chat').scrollTop = document.getElementById('chat').scrollHeight;
    return div;
  }

  async function send() {
    if (!currentConvId) await newConv();
    const input = document.getElementById('prompt');
    const text = input.value.trim();
    if (!text) return;
    input.value = '';

    addBubble('user', text);
    messages.push({ role: 'user', content: text });
    await fetch('/api/messages', {
      method: 'POST', headers: {'Content-Type':'application/json'},
      body: JSON.stringify({ conversation_id: currentConvId, role: 'user', content: text })
    });

    const aiDiv = addBubble('ai', '...');
    const res = await fetch('/api/chat', {
      method: 'POST', headers: {'Content-Type':'application/json'},
      body: JSON.stringify({ messages })
    });

    if (!res.ok) {
      aiDiv.innerText = 'خطأ في الاتصال بالخادم.';
      return;
    }

    aiDiv.innerText = '';
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let fullText = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = decoder.decode(value, { stream: true });
      const lines = chunk.split('\\n').filter(l => l.trim() !== '');
      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const dataStr = line.replace('data: ', '').trim();
          if (dataStr === '[DONE]') break;
          try {
            const data = JSON.parse(dataStr);
            if (data.choices && data.choices[0].delta && data.choices[0].delta.content) {
              fullText += data.choices[0].delta.content;
              aiDiv.innerText = fullText;
              document.getElementById('chat').scrollTop = document.getElementById('chat').scrollHeight;
            }
          } catch(e) {}
        }
      }
    }
    messages.push({ role: 'assistant', content: fullText });
    await fetch('/api/messages', {
      method: 'POST', headers: {'Content-Type':'application/json'},
      body: JSON.stringify({ conversation_id: currentConvId, role: 'assistant', content: fullText })
    });
  }
  loadConvs();
</script>
</body>
</html>
  `);
});

// API Routes
app.get('/api/conversations', (req, res) => {
  res.json(db.prepare('SELECT * FROM conversations ORDER BY id DESC').all());
});

app.get('/api/conversations/:id/messages', (req, res) => {
  res.json(db.prepare('SELECT role, content FROM messages WHERE conversation_id = ? ORDER BY id ASC').all(req.params.id));
});

app.post('/api/conversations', (req, res) => {
  const info = db.prepare('INSERT INTO conversations (title) VALUES (?)').run('محادثة جديدة');
  res.json({ id: info.lastInsertRowid });
});

app.post('/api/messages', (req, res) => {
  const { conversation_id, role, content } = req.body;
  db.prepare('INSERT INTO messages (conversation_id, role, content) VALUES (?, ?, ?)').run(conversation_id, role, content);
  res.sendStatus(200);
});

app.post('/api/chat', async (req, res) => {
  const { messages } = req.body;
  const API_KEY = process.env.OPENAI_API_KEY;
  
  if (!API_KEY) return res.status(500).json({ error: "Missing API Key" });

  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + API_KEY
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        messages: messages,
        stream: true
      })
    });

    if (!response.ok) {
      const err = await response.text();
      return res.status(response.status).send(err);
    }
    
    res.setHeader('Content-Type', 'text/event-stream');
    const reader = response.body.getReader();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      res.write(value);
    }
    res.end();
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  console.log('Server running on http://localhost:' + PORT);
});