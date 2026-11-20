import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";

// 使用 Node 内置测试器执行真实确认脚本，只模拟浏览器事件和原生 dialog 接口。
class FakeEvent {
  constructor(type, target) {
    this.type = type;
    this.target = target;
    this.defaultPrevented = false;
    this.propagationStopped = false;
  }

  preventDefault() {
    this.defaultPrevented = true;
  }

  stopImmediatePropagation() {
    this.propagationStopped = true;
  }
}

class FakeElement {
  constructor(document, id = "", attributes = {}) {
    this.document = document;
    this.id = id;
    this.attributes = attributes;
    this.parentElement = null;
    this.isConnected = true;
    this.disabled = false;
    this.listeners = new Map();
    this.textContent = "";
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  getAttribute(name) {
    return this.attributes[name] ?? null;
  }

  closest(selector) {
    let element = this;
    while (element) {
      if (selector === "[phx-confirm]" && element.getAttribute("phx-confirm") !== null) return element;
      element = element.parentElement;
    }
    return null;
  }

  click() {
    if (this.disabled || !this.isConnected) return;
    this.document.activeElement = this;
    this.document.dispatchClick(this);
  }

  focus() {
    this.document.activeElement = this;
  }

  dispatch(type) {
    const event = new FakeEvent(type, this);
    for (const listener of this.listeners.get(type) ?? []) listener(event);
    return event;
  }
}

class FakeDialog extends FakeElement {
  constructor(document, id) {
    super(document, id);
    this.open = false;
    this.returnValue = "";
    this.previousFocus = null;
  }

  showModal() {
    this.previousFocus = this.document.activeElement;
    this.open = true;
    this.document.getElementById("phx-confirm-cancel").focus();
  }

  close(returnValue = "") {
    this.returnValue = returnValue;
    this.open = false;
    this.document.activeElement = this.previousFocus;
    this.dispatch("close");
  }
}

class FakeDocument {
  constructor() {
    this.elements = new Map();
    this.captureListeners = [];
    this.bubbleListeners = [];
    this.activeElement = null;
  }

  register(element) {
    this.elements.set(element.id, element);
    return element;
  }

  querySelector(selector) {
    return selector === "meta[name='csrf-token']"
      ? { getAttribute: () => "test-token" }
      : null;
  }

  getElementById(id) {
    return this.elements.get(id) ?? null;
  }

  addEventListener(type, listener, capture = false) {
    if (type !== "click") return;
    (capture ? this.captureListeners : this.bubbleListeners).push(listener);
  }

  dispatchClick(target) {
    const event = new FakeEvent("click", target);
    for (const listener of this.captureListeners) listener(event);
    if (event.propagationStopped) return event;
    for (const listener of target.listeners.get("click") ?? []) listener(event);
    if (event.propagationStopped) return event;
    for (const listener of this.bubbleListeners) listener(event);
    return event;
  }
}

const confirmStart = "const csrfToken = document.querySelector";
const confirmEnd = "// 任务和用户删除共用原生 dialog 的打开、关闭和焦点行为。";
const sourcePath = path.resolve(import.meta.dirname, "../../priv/static/js/live_socket.js");

async function createHarness() {
  const source = await readFile(sourcePath, "utf8");
  const start = source.indexOf(confirmStart);
  const end = source.indexOf(confirmEnd, start);
  assert.notEqual(start, -1, "找不到共享确认脚本入口");
  assert.notEqual(end, -1, "找不到共享确认脚本结束位置");

  const document = new FakeDocument();
  const dialog = document.register(new FakeDialog(document, "phx-confirm-dialog"));
  const message = document.register(new FakeElement(document, "phx-confirm-message"));
  const cancel = document.register(new FakeElement(document, "phx-confirm-cancel"));
  const close = document.register(new FakeElement(document, "phx-confirm-close"));
  const accept = document.register(new FakeElement(document, "phx-confirm-accept"));
  const sandbox = { document, Element: FakeElement, WeakSet };
  vm.runInNewContext(source.slice(start, end), sandbox, { filename: sourcePath });

  let actionCount = 0;
  document.addEventListener("click", (event) => {
    if (event.target.closest("[phx-confirm]")) actionCount += 1;
  });

  function createAction() {
    return document.register(new FakeElement(document, "danger-action", { "phx-confirm": "确认执行此操作吗？" }));
  }

  return {
    accept,
    actionCount: () => actionCount,
    cancel,
    close,
    createAction,
    dialog,
    document,
    message
  };
}

test("取消确认不触发 LiveView 操作", async () => {
  const harness = await createHarness();
  const action = harness.createAction();
  action.click();

  assert.equal(harness.dialog.open, true);
  assert.equal(harness.message.textContent, "确认执行此操作吗？");
  assert.equal(harness.actionCount(), 0);
  harness.cancel.click();
  assert.equal(harness.dialog.open, false);
  assert.equal(harness.actionCount(), 0);
});

test("Escape 关闭确认框且不触发操作", async () => {
  const harness = await createHarness();
  const action = harness.createAction();
  action.click();

  harness.dialog.close("");
  assert.equal(harness.dialog.open, false);
  assert.equal(harness.actionCount(), 0);
});

test("确认嵌套图标发起的操作只触发一次", async () => {
  const harness = await createHarness();
  const action = harness.createAction();
  const icon = new FakeElement(harness.document, "icon");
  icon.parentElement = action;
  icon.click();

  assert.equal(harness.dialog.open, true);
  harness.accept.click();
  assert.equal(harness.dialog.open, false);
  assert.equal(harness.actionCount(), 1);
});

test("禁用按钮不会打开确认框或触发操作", async () => {
  const harness = await createHarness();
  const action = harness.createAction();
  action.disabled = true;
  action.click();

  assert.equal(harness.dialog.open, false);
  assert.equal(harness.actionCount(), 0);
});

test("目标按钮在确认前被移除时不触发操作", async () => {
  const harness = await createHarness();
  const action = harness.createAction();
  action.click();
  action.isConnected = false;
  harness.accept.click();

  assert.equal(harness.dialog.open, false);
  assert.equal(harness.actionCount(), 0);
});
