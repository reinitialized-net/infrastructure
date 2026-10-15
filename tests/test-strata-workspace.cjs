// PLAYWRIGHT_MODULE and CHROMIUM_EXECUTABLE select the test runner, not shipped dependencies.
// STRATA_WEB_ROOT is the built harness's share/strata/serve/web directory.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE});
 try {
 const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('https://strata.test/**',async route=>{
   const u=new URL(route.request().url()), root=process.env.STRATA_WEB_ROOT;
   if(u.pathname==='/' || u.pathname.startsWith('/web/')){
     const file=path.join(root,u.pathname==='/'?'index.html':u.pathname.slice(5));
     const type=file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':file.endsWith('.svg')?'image/svg+xml':'text/html';
     await route.fulfill({contentType:type,body:fs.readFileSync(file)});return;
   }
   const values={'/health':{status:'ok',model:'test-model',loaded:true,max_context:131072},'/mcp':{servers:[],tools:0},'/metrics':{},'/settings':{},'/config':{}};
   await route.fulfill({contentType:'application/json',body:JSON.stringify(values[u.pathname]||{})});
 });
 await page.goto('https://strata.test/');
 await page.getByRole('button',{name:'Chats & projects',exact:true}).waitFor();
 await page.evaluate(async()=>{ messages=[{role:'user',text:'Data fixture',files:[{kind:'file',name:'sales.csv',text:'amount\n42'}],time:Date.now()},{role:'assistant',text:'```html\n<h1>Safe preview</h1><script>parent.hacked=true</script>\n```',time:Date.now()}];await saveChat();renderChat(); });
 await page.reload();await page.getByRole('button',{name:'Chats & projects',exact:true}).waitFor();
 assert.equal(await page.evaluate(()=>messages[0].files[0].text),'amount\n42');
 await page.getByRole('button',{name:'Preview',exact:true}).click();
 assert.equal(await page.locator('iframe').getAttribute('sandbox'),'');
 assert.equal(await page.evaluate(()=>window.hacked),undefined);
 await page.getByRole('button',{name:'Close',exact:true}).click();
 await page.getByRole('button',{name:'Edit & branch',exact:true}).click();
 assert.equal(await page.locator('#input').inputValue(),'Data fixture');
 assert.equal(await page.evaluate(()=>attachments[0].text),'amount\n42');
 await page.getByRole('button',{name:'Chats & projects',exact:true}).click();
 await page.getByRole('button',{name:'Data fixture',exact:true}).click();
 assert.equal(await page.evaluate(()=>messages.length),2);
 await page.getByRole('button',{name:'Instructions',exact:true}).click();
 await page.getByRole('textbox',{name:'Project name',exact:true}).fill('Research');
 await page.getByRole('textbox',{name:'Preferences and context for this chat',exact:true}).fill('Use concise answers.');
 await page.getByRole('button',{name:'Save instructions',exact:true}).click();
 assert.equal(await page.evaluate(()=>apiMessages()[0].content),'Use concise answers.');
 await page.getByRole('button',{name:'New chat',exact:true}).click();
 await page.getByRole('button',{name:'Chats & projects',exact:true}).click();
 await page.getByRole('textbox',{name:'Search chats, content, or project',exact:true}).fill('Data fixture');
 await page.getByRole('button',{name:'Research / Data fixture',exact:true}).click();
 assert.equal(await page.evaluate(()=>messages[0].files[0].text),'amount\n42');
 assert.deepEqual(errors,[]);
 console.log('PASS: attachment reload, history, search, instructions, edit branch, sandboxed preview');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
