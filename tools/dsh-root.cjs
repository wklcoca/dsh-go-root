#!/usr/bin/env node
'use strict'
// dsh-root: 在 proot 之外、以真 root 执行命令（App 侧 su）。读取 App 启动时写入的
// /var/lib/dsh-app/root/bridge.json，连到专用抽象 socket 调用 root_exec 工具。
const fs = require('fs')
const net = require('net')
const CFG = process.env.DSH_ROOT_CFG || '/var/lib/dsh-app/root/bridge.json'

let cfg
try { cfg = JSON.parse(fs.readFileSync(CFG, 'utf8')) }
catch (e) { console.error('root exec 通道未就绪（' + CFG + '）：' + e.message); process.exit(3) }

const argv = process.argv.slice(2)
let bg = false, timeoutMs = 120000, parts = []
for (let i = 0; i < argv.length; i++) {
  const a = argv[i]
  if (a === '--bg' || a === '--background') bg = true
  else if (a === '--timeout') timeoutMs = parseInt(argv[++i], 10) || 120000
  else if (a === '-h' || a === '--help') { console.log('用法: dsh-root [--bg] [--timeout ms] "<命令>"'); process.exit(0) }
  else parts.push(a)
}
const cmd = parts.join(' ').trim()
if (!cmd) { console.error('用法: dsh-root [--bg] [--timeout ms] "<命令>"'); process.exit(2) }

const targets = []
if (cfg.abstract) targets.push({ path: '\0' + cfg.abstract })
if (cfg.tcpPort) targets.push({ port: cfg.tcpPort, host: '127.0.0.1' })

function attempt (i) {
  if (i >= targets.length) { console.error('连不上 root exec 通道（App 未就绪/已被杀）'); process.exit(4) }
  const s = net.connect(targets[i])
  let up = false
  s.on('connect', () => {
    up = true
    s.write(JSON.stringify({ dshPhone: 1, token: String(cfg.token || '') }) + '\n')
    s.write(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'root_exec', arguments: { cmd, timeout_ms: timeoutMs, background: bg } } }) + '\n')
  })
  let buf = ''
  s.on('data', (d) => {
    buf += d.toString('utf8')
    let k
    while ((k = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, k); buf = buf.slice(k + 1)
      let m; try { m = JSON.parse(line) } catch (e) { continue }
      if (m.id === 1) {
        const r = m.result
        const txt = r && r.content && r.content[0] && r.content[0].text
        if (txt != null) process.stdout.write(txt + '\n')
        if (m.error) { console.error('错误: ' + JSON.stringify(m.error)); s.end(); process.exit(6) }
        if (r && r.isError) { s.end(); process.exit(1) }
        s.end(); process.exit(0)
      }
    }
  })
  s.on('error', (e) => { if (!up) attempt(i + 1); else { console.error('连接错误 ' + e.code); process.exit(5) } })
  s.on('close', () => { if (up) process.exit(0) })
}
attempt(0)
