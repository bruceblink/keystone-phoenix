const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const Hooks = {
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

