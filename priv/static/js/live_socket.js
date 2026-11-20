const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const Hooks = {
  JobDeleteDialog: {
    mounted() {
      // 原生 dialog 管理焦点；关闭事件再同步到 LiveView 服务端状态。
      this.handleClose = () => {
        if (this.el.dataset.open === "true") this.pushEvent("close-modal", {});
      };
      this.el.addEventListener("close", this.handleClose);
      this.syncOpenState();
    },
    updated() {
      this.syncOpenState();
    },
    syncOpenState() {
      if (this.el.dataset.open === "true" && !this.el.open) {
        const invoker = document.getElementById(this.el.dataset.invokerId);
        if (invoker && document.activeElement !== invoker) invoker.focus({ preventScroll: true });
        this.el.showModal();
      }
      if (this.el.dataset.open !== "true" && this.el.open) this.el.close();
    },
    destroyed() {
      this.el.removeEventListener("close", this.handleClose);
      if (this.el.open) this.el.close();
    }
  },
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

