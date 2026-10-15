import { createInterface } from 'node:readline';
const send = (message) => process.stdout.write(JSON.stringify(message) + '\n');
let initialized = false;
let active = false;
createInterface({ input: process.stdin }).on('line', (line) => {
  const message = JSON.parse(line);
  if (message.method === 'initialize') return send({ id: message.id, result: { userAgent: 'fixture' } });
  if (message.method === 'initialized') { initialized = true; return; }
  if (!initialized) throw new Error('Missing initialized notification');
  if (message.method === 'thread/start') return send({ id: message.id, result: { thread: { id: 'fixture-thread', cwd: process.cwd(), preview: 'fixture', turns: [] } } });
  if (message.method === 'model/list') return send({ id: message.id, result: { data: [{ id: 'fixture-model' }] } });
  if (message.method === 'turn/start') {
    active = true;
    send({ id: message.id, result: { turn: { id: 'fixture-turn', status: 'inProgress', items: [{ type: 'commandExecution', aggregatedOutput: 'private output' }] } } });
    send({ method: 'item/commandExecution/outputDelta', params: { threadId: 'fixture-thread', turnId: 'fixture-turn', delta: 'private output' } });
    send({ id: 'native-approval-id', method: 'item/commandExecution/requestApproval', params: { threadId: 'fixture-thread', turnId: 'fixture-turn', command: 'fixture-test' } });
    return;
  }
  if (message.id === 'native-approval-id' && message.result) {
    if (!active || message.result.decision !== 'accept') throw new Error('Invalid original approval response');
    send({ method: 'serverRequest/resolved', params: { threadId: 'fixture-thread', requestId: 'native-approval-id' } });
    send({ method: 'item/agentMessage/delta', params: { threadId: 'fixture-thread', turnId: 'fixture-turn', itemId: 'fixture-item', delta: 'approved' } });
    send({ method: 'turn/completed', params: { threadId: 'fixture-thread', turn: { id: 'fixture-turn', status: 'completed' } } });
    return;
  }
});
