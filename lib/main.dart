<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AI Chat</title>
<style>
  body { display: flex; flex-direction: column; height: 100vh; margin: 0; font-family: sans-serif; background: #212121; color: #ececec; }
  #chat { flex: 1; padding: 15px; overflow-y: auto; display: flex; flex-direction: column; gap: 10px; }
  .msg { max-width: 85%; padding: 10px 14px; border-radius: 8px; line-height: 1.5; white-space: pre-wrap; font-size: 15px; }
  .user { background: #2f2f2f; align-self: flex-start; }
  .ai { background: transparent; align-self: flex-end; }
  #input-area { padding: 10px; background: #171717; display: flex; gap: 10px; }
  #prompt { flex: 1; padding: 12px; background: #2f2f2f; border: 1px solid #444; border-radius: 8px; color: white; resize: none; font-size: 16px; outline: none; }
  #send-btn { background: #10a37f; color: white; border: none; border-radius: 8px; padding: 0 20px; font-size: 16px; cursor: pointer; }
</style>
</head>
<body>
<div id="chat"></div>
<div id="input-area">
  <textarea id="prompt" rows="1" placeholder="اكتب رسالتك..." onkeydown="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();send()}"></textarea>
  <button id="send-btn" onclick="send()">إرسال</button>
</div>
<script>
  // ضع مفتاح API هنا
  const API_KEY = 'sk-...'; 
  const API_URL = 'https://api.openai.com/v1/chat/completions';
  const MODEL = 'gpt-4o';
  
  let messages = [];

  function addBubble(role, text) {
    const div = document.createElement('div');
    div.className = 'msg ' + role;
    div.innerText = text;
    document.getElementById('chat').appendChild(div);
    document.getElementById('chat').scrollTop = document.getElementById('chat').scrollHeight;
    return div;
  }

  async function send() {
    const input = document.getElementById('prompt');
    const text = input.value.trim();
    if (!text) return;
    input.value = '';

    addBubble('user', text);
    messages.push({ role: 'user', content: text });

    const aiDiv = addBubble('ai', '...');
    
    try {
      const res = await fetch(API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + API_KEY
        },
        body: JSON.stringify({ model: MODEL, messages: messages, stream: true })
      });

      if (!res.ok) throw new Error('HTTP ' + res.status);

      aiDiv.innerText = '';
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let fullText = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        const chunk = decoder.decode(value, { stream: true });
        const lines = chunk.split('\n').filter(l => l.trim() !== '');
        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const dataStr = line.replace('data: ', '').trim();
            if (dataStr === '[DONE]') break;
            try {
              const data = JSON.parse(dataStr);
              if (data.choices[0].delta.content) {
                fullText += data.choices[0].delta.content;
                aiDiv.innerText = fullText;
              }
            } catch(e) {}
          }
        }
      }
      messages.push({ role: 'assistant', content: fullText });
    } catch (error) {
      aiDiv.innerText = 'خطأ: ' + error.message;
    }
  }
</script>
</body>
</html>