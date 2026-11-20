const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
// 在 LiveView 发送事件前拦截需确认的操作；用户确认后只重放一次原按钮事件。
const confirmationDialog = document.getElementById("phx-confirm-dialog");
const approvedConfirmActions = new WeakSet();
let pendingConfirmAction = null;

if (confirmationDialog) {
  const confirmationMessage = document.getElementById("phx-confirm-message");
  const confirmAction = document.getElementById("phx-confirm-accept");
  document.addEventListener("click", (event) => {
    const action = event.target instanceof Element ? event.target.closest("[phx-confirm]") : null;
    if (!action || action.disabled || approvedConfirmActions.has(action)) {
      if (action && approvedConfirmActions.has(action)) approvedConfirmActions.delete(action);
      return;
    }
    event.preventDefault();
    event.stopImmediatePropagation();
    pendingConfirmAction = action;
    confirmationMessage.textContent = action.getAttribute("phx-confirm") || "请确认此操作。";
    confirmationDialog.returnValue = "";
    confirmationDialog.showModal();
  }, true);
  document.getElementById("phx-confirm-cancel").addEventListener("click", () => confirmationDialog.close("cancel"));
  document.getElementById("phx-confirm-close").addEventListener("click", () => confirmationDialog.close("cancel"));
  confirmAction.addEventListener("click", () => confirmationDialog.close("confirm"));
  confirmationDialog.addEventListener("close", () => {
    const action = pendingConfirmAction;
    pendingConfirmAction = null;
    if (confirmationDialog.returnValue === "confirm" && action?.isConnected && !action.disabled) {
      approvedConfirmActions.add(action);
      action.click();
    }
    confirmationDialog.returnValue = "";
  });
}
// 任务和用户删除共用原生 dialog 的打开、关闭和焦点行为。
const nativeConfirmDialog = (closeEvent) => ({
  mounted() {
    this.handleClose = () => {
      // 将原生关闭请求延后到本轮 DOM patch 后，区分 Escape 和 LiveView 临时移除 open 属性。
      queueMicrotask(() => {
        if (this.el.dataset.open === "true" && !this.el.open) this.pushEvent(closeEvent, {});
      });
    };
    this.el.addEventListener("close", this.handleClose);
    this.wasOpen = false;
    this.syncOpenState();
  },
  updated() {
    this.syncOpenState();
  },
  syncOpenState() {
    const shouldOpen = this.el.dataset.open === "true";
    if (shouldOpen && !this.el.open) {
      const invoker = document.getElementById(this.el.dataset.invokerId);
      if (invoker && document.activeElement !== invoker) invoker.focus({ preventScroll: true });
      this.el.showModal();
    }
    if (!shouldOpen && this.wasOpen) {
      const invokerId = this.el.dataset.invokerId;
      if (this.el.open) this.el.close();
      // LiveView 收到取消事件后会更新 DOM；下一帧将焦点还给更新后的触发按钮。
      requestAnimationFrame(() => {
        const invoker = document.getElementById(invokerId);
        if (invoker?.isConnected && !invoker.disabled) invoker.focus({ preventScroll: true });
      });
    }
    this.wasOpen = shouldOpen;
  },
  destroyed() {
    this.el.removeEventListener("close", this.handleClose);
    if (this.el.open) this.el.close();
  }
});
const Hooks = {
  UserDeleteDialog: nativeConfirmDialog("close-user-delete"),
  JobDeleteDialog: nativeConfirmDialog("close-modal"),
  LocalDateTime: {
    mounted() {
      this.formatTime();
    },
    updated() {
      this.formatTime();
    },
    formatTime() {
      // 服务端传 UTC 时间戳；浏览器按本地时区显示，与 admin-web 使用同一格式。
      const value = this.el.dataset.utcTime || "";
      const date = new Date(value);
      this.el.textContent = Number.isNaN(date.getTime())
        ? value || "—"
        : date.toLocaleString("zh-CN", { hour12: false });
    }
  },
  LocalDateTimeInput: {
    mounted() {
      // datetime-local 没有时区；提交时按浏览器本地时间转换成 API 使用的 UTC ISO 时间。
      this.syncUtc = () => {
        const localInput = this.el.querySelector("#api-key-expires-local");
        const hidden = this.el.querySelector("input[name='expiresAt']");
        if (!hidden) return;
        const localValue = localInput?.value || "";
        const date = new Date(localValue);
        hidden.value = !localValue
          ? ""
          : Number.isNaN(date.getTime())
            ? localValue
            : date.toISOString();
      };
      this.handleLocalInput = (event) => {
        if (event.target?.id === "api-key-expires-local") this.syncUtc();
      };
      this.el.addEventListener("input", this.handleLocalInput, true);
      this.el.addEventListener("change", this.handleLocalInput, true);
      this.syncUtc();
    },
    updated() {
      this.syncUtc();
    },
    destroyed() {
      this.el.removeEventListener("input", this.handleLocalInput, true);
      this.el.removeEventListener("change", this.handleLocalInput, true);
    }
  },
  DownloadFile: {
    mounted() {
      this.handleEvent("download-xlsx", (payload) => {
        // 服务端只推送当前授权结果，浏览器在本地生成一次性下载文件。
        const content = payload.content || "";
        const contentType = payload.content_type || payload.contentType;
        const bytes = Uint8Array.from(atob(content), (character) => character.charCodeAt(0));
        const blob = new Blob([bytes], { type: contentType });
        const link = document.createElement("a");
        const objectUrl = URL.createObjectURL(blob);
        link.href = objectUrl;
        link.download = payload.filename;
        document.body.appendChild(link);
        link.click();
        link.remove();
        setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
      });
    }
  }
};
const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
});
liveSocket.connect();
window.liveSocket = liveSocket;

