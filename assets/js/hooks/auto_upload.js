// Generic hook for auto-uploading files when selected
export const AutoUpload = {
  mounted() {
    // Add a small delay to ensure forms are fully rendered
    setTimeout(() => {
      this.setupAutoUpload();
    }, 100);
    
    // Listen for upload completion to clear the file input
    this.handleEvent("upload-complete", () => {
      this.clearFileInputs();
    });
  },
  
  updated() {
    // Re-attach listeners when the DOM updates with a small delay
    setTimeout(() => {
      this.setupAutoUpload();
    }, 100);
  },
  
  clearFileInputs() {
    const fileInputs = this.el.querySelectorAll('input[type="file"]');
    fileInputs.forEach(input => {
      input.value = '';
    });
  },
  
  setupAutoUpload() {
    // Remove any existing listeners to avoid duplicates
    if (this.fileChangeHandlers) {
      this.fileChangeHandlers.forEach(({input, handler}) => {
        input.removeEventListener('change', handler);
      });
    }
    
    this.fileChangeHandlers = [];
    
    // Find all file inputs and their associated submit buttons
    const forms = this.el.querySelectorAll('form[data-auto-upload="true"]');
    
    // Forms with data-auto-upload rely entirely on `allow_upload(auto_upload:
    // true)` plus each LiveComponent's own `progress:` callback to start and
    // finish the upload - no client-side submit is needed for either. This
    // hook used to also click the hidden submit button ~100ms after file
    // selection, firing a second, redundant "save_*"/"upload_*" event that
    // raced the server-side auto-consumption: whichever handler lost tried
    // to consume an upload entry whose channel process had already exited,
    // crashing the LiveView. Nothing left to attach here; kept as a no-op
    // pass so mounted()/updated() stay cheap to call.
    void forms;
  },
  
  destroyed() {
    // Clean up event listeners
    if (this.fileChangeHandlers) {
      this.fileChangeHandlers.forEach(({input, handler}) => {
        input.removeEventListener('change', handler);
      });
    }
  }
};
export default AutoUpload;
