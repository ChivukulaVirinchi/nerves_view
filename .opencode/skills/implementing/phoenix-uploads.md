---
name: elixir-phoenix-uploads
description: >
  Phoenix LiveView file uploads covering allow_upload configuration,
  consume_uploaded_entries, auto-upload, progress tracking, error handling,
  external (S3) uploads, and security. ALWAYS use when implementing file
  uploads in LiveView. For general form patterns -> load phoenix-forms. For
  upload testing -> load testing.
---

# Phoenix LiveView File Uploads

LiveView file uploads have a specific lifecycle: configure with `allow_upload`,
render with `live_file_input`, track with entries/progress, consume with
`consume_uploaded_entries`. LLMs consistently forget that `consume_uploaded_entries`
is required (files are auto-cleaned otherwise), miss the `{:ok, value}` return
requirement in the consume callback, and skip error handling for upload validation
failures.

## 1. Rules

1. **Always call `consume_uploaded_entries/3` or `consume_uploaded_entry/3`.** Without consumption, uploaded files are automatically cleaned up and lost.
2. **Always return `{:ok, value}` from the consume callback.** Any other return shape causes a runtime error.
3. **Always include `phx-change` on the upload form.** Uploads require the change event to process file selection and validation.
4. **Always provide a `cancel_upload` handler.** Users must be able to remove selected files before submission.
5. **Always validate file type server-side.** The `accept` option is a client-side hint only; it can be bypassed.
6. **Always generate unique filenames.** Use `entry.uuid` to prevent collisions and path traversal attacks.
7. **Always sanitize `entry.client_name` before using in file paths.** Client-provided filenames can contain path traversal characters (`../`).
8. **Set `max_file_size` to a reasonable limit.** The default is 8MB; adjust based on use case.
9. **Use external uploads (S3) for production multi-instance deployments.** Local file storage in `priv/static/uploads` only works for single-instance and triggers LiveReload in dev.
10. **Never call `consume_uploaded_entries` while entries are still uploading.** It raises `ArgumentError`. Check `entry.done?` or consume only in the submit handler.

## 2. Decision Tables

### 2.1 Upload Mode Selection

| Situation | Mode | Configuration | Why |
|-----------|------|---------------|-----|
| Standard form with submit button | Manual (default) | `allow_upload(:field, ...)` | Files upload on form submit; user controls timing |
| Upload immediately on file selection | Auto | `allow_upload(:field, auto_upload: true, progress: &handler/3)` | Better UX for avatar/profile image; no submit needed |
| Large files or production multi-node | External (S3) | `allow_upload(:field, external: &presign/2)` | Files go directly to S3; server never handles binary |
| Multiple file types on one form | Multiple upload configs | Separate `allow_upload` for each field | Each field has its own accept/max rules |

### 2.2 Storage Destination Selection

| Environment | Storage | Path Pattern | Why |
|-------------|---------|-------------|-----|
| Development | Local filesystem | `priv/static/uploads/#{uuid}-#{basename}` | Simple, no external deps |
| Single-instance production | Local filesystem + persistent volume | `/app/uploads/#{uuid}-#{basename}` | Works without S3; needs volume mount |
| Multi-instance production | S3/GCS/R2 via external upload | Presigned URL from `external` callback | Files must be accessible from any instance |
| Testing | Local temp directory | `System.tmp_dir!/0` | Cleaned up automatically |

### 2.3 Error Handling Strategy

| Error | Source | User Message | Handler |
|-------|--------|-------------|---------|
| `:too_large` | File exceeds `max_file_size` | "File too large (max X MB)" | `upload_errors/2` in template |
| `:too_many_files` | Exceeds `max_entries` | "Too many files (max N)" | `upload_errors/1` on upload ref |
| `:not_accepted` | File type not in `accept` list | "File type not supported" | `upload_errors/2` in template |
| `:external_client_failure` | S3 presign or upload failed | "Upload failed, please retry" | `upload_errors/2` in template |
| Custom validation | `validate` callback in `allow_upload` | Domain-specific message | Custom validation function |

### 2.4 Progress Tracking

| Upload Mode | Progress Source | How to Display |
|-------------|----------------|---------------|
| Manual upload | `entry.progress` (0-100) | `<progress value={entry.progress} max="100">` |
| Auto upload | `entry.progress` in progress callback | Same, updated on each chunk |
| External upload | Client-side progress events | JavaScript hook + `pushEvent` |

## 3. Patterns (BAD -> GOOD)

### 3.1 Missing consume_uploaded_entries

**Severity:** BLOCK

```elixir
# BAD -- files are uploaded but never consumed, auto-cleaned
def handle_event("save", _params, socket) do
  # where did the files go? They were cleaned up!
  {:noreply, socket}
end

# GOOD -- consume files during save
def handle_event("save", _params, socket) do
  uploaded_files =
    consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
      dest = Path.join(upload_dir(), "#{entry.uuid}-#{sanitize(entry.client_name)}")
      File.cp!(path, dest)
      {:ok, "/uploads/#{Path.basename(dest)}"}
    end)

  {:noreply, assign(socket, uploaded_files: uploaded_files)}
end
```

**Why:** LiveView stores uploaded files in a temporary directory. If you don't call `consume_uploaded_entries`, the files are automatically deleted when the LiveView process terminates or the upload ref is garbage collected.

### 3.2 Wrong Return from Consume Callback

**Severity:** BLOCK

```elixir
# BAD -- returning bare value instead of {:ok, value}
consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
  dest = Path.join(upload_dir(), Path.basename(path))
  File.cp!(path, dest)
  "/uploads/#{Path.basename(dest)}"  # missing {:ok, ...} wrapper!
end)

# GOOD -- always return {:ok, value}
consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
  dest = Path.join(upload_dir(), Path.basename(path))
  File.cp!(path, dest)
  {:ok, "/uploads/#{Path.basename(dest)}"}
end)
```

**Why:** `consume_uploaded_entries/3` expects the callback to return `{:ok, value}`. The `value` is collected into the result list. Returning a bare value causes a pattern match error at runtime.

### 3.3 Missing phx-change on Upload Form

**Severity:** BLOCK

```heex
<%!-- BAD -- uploads don't work without phx-change --%>
<.form for={@form} id="upload-form" phx-submit="save">
  <.live_file_input upload={@uploads.avatar} />
  <.button type="submit">Upload</.button>
</.form>

<%!-- GOOD -- phx-change required for file selection events --%>
<.form for={@form} id="upload-form" phx-change="validate" phx-submit="save">
  <.live_file_input upload={@uploads.avatar} />
  <.button type="submit">Upload</.button>
</.form>
```

**Why:** When a user selects a file, LiveView sends a change event to process the selection and run upload validations. Without `phx-change`, the file selection event has nowhere to go, and the upload silently fails.

### 3.4 Unsanitized Client Filename

**Severity:** BLOCK

```elixir
# BAD -- path traversal vulnerability
consume_uploaded_entries(socket, :doc, fn %{path: path}, entry ->
  dest = Path.join("priv/static/uploads", entry.client_name)
  # entry.client_name could be "../../../etc/passwd"
  File.cp!(path, dest)
  {:ok, dest}
end)

# GOOD -- sanitize and prefix with UUID
consume_uploaded_entries(socket, :doc, fn %{path: path}, entry ->
  safe_name = "#{entry.uuid}-#{Path.basename(entry.client_name)}"
  dest = Path.join("priv/static/uploads", safe_name)
  File.cp!(path, dest)
  {:ok, "/uploads/#{safe_name}"}
end)
```

**Why:** `entry.client_name` is user-controlled. It can contain `../` sequences that write files outside the upload directory. `Path.basename/1` strips directory components, and the UUID prefix ensures uniqueness.

### 3.5 Missing Cancel Upload Handler

**Severity:** WARN

```elixir
# BAD -- no way to remove selected files
# (template has file list but no cancel button)

# GOOD -- cancel handler + template button
def handle_event("cancel-upload", %{"ref" => ref}, socket) do
  {:noreply, cancel_upload(socket, :avatar, ref)}
end
```

```heex
<%= for entry <- @uploads.avatar.entries do %>
  <.live_img_preview entry={entry} width="100" />
  <span>{entry.client_name}</span>
  <progress value={entry.progress} max="100">{entry.progress}%</progress>
  <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref}>
    Cancel
  </button>
  <%= for err <- upload_errors(@uploads.avatar, entry) do %>
    <p class="text-red-500">{error_to_string(err)}</p>
  <% end %>
<% end %>
```

**Why:** Without a cancel mechanism, users who select the wrong file must reload the page. This is especially important for multi-file uploads where one bad file shouldn't block the rest.

### 3.6 Client-Only File Type Validation

**Severity:** WARN

```elixir
# BAD -- trusting accept alone
allow_upload(:avatar, accept: ~w(.jpg .png))
# The accept attribute is a browser hint; curl/scripts bypass it

# GOOD -- server-side validation in addition to accept
allow_upload(:avatar,
  accept: ~w(.jpg .jpeg .png .webp),
  max_entries: 1,
  max_file_size: 5_000_000
)

# For content-type validation, add a custom validate function:
allow_upload(:document,
  accept: ~w(.pdf .docx),
  max_entries: 5,
  max_file_size: 10_000_000
)

# In the validate handler, check entries:
def handle_event("validate", _params, socket) do
  {:noreply, socket}  # allow_upload validations run automatically
end
```

**Why:** The HTML `accept` attribute filters the file picker dialog but doesn't prevent malicious uploads. A user can modify the request or use tools that bypass browser restrictions. Server-side `max_file_size` is enforced per chunk.

### 3.7 Local Storage in Multi-Instance Production

**Severity:** WARN

```elixir
# BAD -- local storage, files only on one instance
consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
  dest = Path.join("priv/static/uploads", "#{entry.uuid}.jpg")
  File.cp!(path, dest)
  {:ok, "/uploads/#{entry.uuid}.jpg"}
end)
# In production with 3 instances, only 1 has the file

# GOOD -- external upload to S3
allow_upload(:avatar,
  accept: ~w(.jpg .jpeg .png),
  max_entries: 1,
  external: &presign_upload/2
)

defp presign_upload(entry, socket) do
  config = Application.get_env(:my_app, :s3)
  key = "uploads/#{entry.uuid}-#{Path.basename(entry.client_name)}"

  {:ok, %{uploader: "S3", key: key, url: presigned_url(config, key)}, socket}
end
```

**Why:** When running multiple instances behind a load balancer, a file written to one instance's filesystem is invisible to other instances. External storage (S3, GCS, R2) makes files accessible from any instance.

### 3.8 Consuming During Upload

**Severity:** BLOCK

```elixir
# BAD -- consuming before upload completes raises ArgumentError
defp handle_progress(:avatar, entry, socket) do
  consume_uploaded_entries(socket, :avatar, fn meta, entry ->
    # CRASH: ArgumentError, entries still uploading
    {:ok, process(meta)}
  end)
  {:noreply, socket}
end

# GOOD -- check entry.done? first, consume single entry
defp handle_progress(:avatar, entry, socket) do
  if entry.done? do
    url =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        dest = Path.join(upload_dir(), "#{entry.uuid}.jpg")
        File.cp!(path, dest)
        {:ok, "/uploads/#{Path.basename(dest)}"}
      end)

    {:noreply, assign(socket, avatar_url: url)}
  else
    {:noreply, socket}
  end
end
```

**Why:** `consume_uploaded_entries` raises if any entry for the upload ref is still in progress. In auto-upload mode, use `consume_uploaded_entry` (singular) on the specific completed entry after checking `entry.done?`.

## 4. Checklist

### Mount Setup
- [ ] `allow_upload` called with `accept`, `max_entries`, and `max_file_size`
- [ ] Form assign initialized (even if just `to_form(%{})`)
- [ ] For auto-upload: `auto_upload: true` and `progress` callback provided

### Template
- [ ] `<.form>` has `id`, `phx-change`, and `phx-submit`
- [ ] `<.live_file_input upload={@uploads.field}>` present inside form
- [ ] Entry list renders preview, filename, progress bar
- [ ] Cancel button with `phx-click="cancel-upload"` and `phx-value-ref={entry.ref}`
- [ ] Error display using `upload_errors(@uploads.field, entry)`
- [ ] General upload errors displayed: `upload_errors(@uploads.field)`

### Event Handlers
- [ ] `handle_event("validate", ...)` exists (even if just `{:noreply, socket}`)
- [ ] `handle_event("save", ...)` calls `consume_uploaded_entries`
- [ ] `handle_event("cancel-upload", ...)` calls `cancel_upload`
- [ ] Consume callback returns `{:ok, value}`

### Security
- [ ] Filenames sanitized with `Path.basename/1`
- [ ] UUID prefix on stored filenames (`entry.uuid`)
- [ ] `max_file_size` set to a reasonable limit
- [ ] Production uses external storage (S3), not local filesystem
- [ ] Content type validated server-side (not just `accept`)

### Error Handling
- [ ] `error_to_string/1` handles `:too_large`, `:too_many_files`, `:not_accepted`
- [ ] Errors displayed per-entry and per-upload-ref

## 5. Complete Manual Upload Pattern

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(form: to_form(%{}), uploaded_files: [])
   |> allow_upload(:avatar,
     accept: ~w(.jpg .jpeg .png .webp),
     max_entries: 1,
     max_file_size: 5_000_000
   )}
end

def handle_event("validate", _params, socket) do
  {:noreply, socket}
end

def handle_event("cancel-upload", %{"ref" => ref}, socket) do
  {:noreply, cancel_upload(socket, :avatar, ref)}
end

def handle_event("save", _params, socket) do
  uploaded_files =
    consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
      safe_name = "#{entry.uuid}-#{Path.basename(entry.client_name)}"
      dest = Path.join("priv/static/uploads", safe_name)
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(path, dest)
      {:ok, "/uploads/#{safe_name}"}
    end)

  {:noreply, update(socket, :uploaded_files, &(&1 ++ uploaded_files))}
end

defp error_to_string(:too_large), do: "File too large (max 5 MB)"
defp error_to_string(:too_many_files), do: "Too many files"
defp error_to_string(:not_accepted), do: "File type not supported"
defp error_to_string(err), do: inspect(err)
```

```heex
<.form for={@form} id="upload-form" phx-change="validate" phx-submit="save">
  <.live_file_input upload={@uploads.avatar} />

  <%= for entry <- @uploads.avatar.entries do %>
    <.live_img_preview entry={entry} width="100" />
    <span>{entry.client_name}</span>
    <progress value={entry.progress} max="100">{entry.progress}%</progress>
    <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref}>
      Cancel
    </button>
    <%= for err <- upload_errors(@uploads.avatar, entry) do %>
      <p class="text-red-500">{error_to_string(err)}</p>
    <% end %>
  <% end %>

  <%= for err <- upload_errors(@uploads.avatar) do %>
    <p class="text-red-500">{error_to_string(err)}</p>
  <% end %>

  <.button type="submit">Upload</.button>
</.form>
```

## 6. Complete Auto-Upload Pattern

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(form: to_form(%{}), avatar_url: nil)
   |> allow_upload(:avatar,
     accept: ~w(.jpg .jpeg .png .webp),
     max_entries: 1,
     max_file_size: 5_000_000,
     auto_upload: true,
     progress: &handle_progress/3
   )}
end

defp handle_progress(:avatar, entry, socket) do
  if entry.done? do
    url =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        safe_name = "#{entry.uuid}-#{Path.basename(entry.client_name)}"
        dest = Path.join("priv/static/uploads", safe_name)
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)
        {:ok, "/uploads/#{safe_name}"}
      end)

    {:noreply, assign(socket, avatar_url: url)}
  else
    {:noreply, socket}
  end
end
```

## 7. Routing

- **General form patterns (validate, submit, nested)** -> load `phoenix-forms`
- **Testing uploads** -> load `testing`
- **Upload security (path traversal, file validation)** -> load `security`
- **HEEx template syntax** -> load `heex`
- **LiveView lifecycle** -> load `liveview-lifecycle`
