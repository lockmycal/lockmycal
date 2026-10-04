defmodule Tymeslot.Utils.DocumentValidator do
  @moduledoc """
  Checks that an uploaded file's content matches its extension, the
  attachment counterpart of `Tymeslot.Utils.MediaValidator`.

  The browser-side `accept` filter and LiveView's extension check only look at
  the file name, and the MIME type a browser reports is just as easy to fake,
  so a renamed executable would pass them. This reads the file itself:

    * `pdf` — starts with the `%PDF-` signature;
    * `zip` — starts with a local-file or empty-archive signature;
    * `docx` / `xlsx` / `pptx` — a readable zip archive (Office Open XML)
      holding the part that makes it a Word document, an Excel workbook or a
      PowerPoint presentation;
    * `odt` / `ods` — a readable zip archive (OpenDocument) whose `mimetype`
      entry names a text document or a spreadsheet;
    * `png` / `jpg` / `jpeg` / `webp` — an image whose own header says it is
      that format (a PNG renamed to `.jpg` is rejected);
    * `svg` — SVG markup with nothing that can run or pull in content:
      no scripts, event-handler attributes, `javascript:` URLs, embedded HTML
      (`foreignObject`, `iframe`, `object`, `embed`) or entity declarations.
      Such a file is rejected rather than cleaned, so what the host receives
      is exactly what the booker sent;
    * `txt` / `md` / `csv` — plain text, i.e. no NUL bytes. The encoding is
      not checked: legacy single-byte encodings (Windows-1250 and the like)
      are common in real text files and just as harmless.
  """

  @text_chunk_bytes 64 * 1024

  # Enough for every image header ExImageInfo reads for these formats.
  @image_header_bytes 64 * 1024

  @image_types %{
    "png" => "image/png",
    "jpg" => "image/jpeg",
    "jpeg" => "image/jpeg",
    "webp" => "image/webp"
  }

  @odf_mimetypes %{
    "odt" => "application/vnd.oasis.opendocument.text",
    "ods" => "application/vnd.oasis.opendocument.spreadsheet"
  }

  # Anything in an SVG that can execute or load other content once the file
  # is opened in a browser.
  @unsafe_svg ~r/<script|<foreignobject|<iframe|<object|<embed|<!entity|javascript:|\son[a-z]+\s*=/i

  @doc """
  True when the file at `path` really is of `extension` (lowercase, without
  the leading dot). Any extension not listed above is rejected.
  """
  @spec valid_file?(String.t(), String.t()) :: boolean()
  def valid_file?(path, "pdf"), do: header_matches?(path, ["%PDF-"])

  def valid_file?(path, "zip"),
    do: header_matches?(path, [<<"PK", 3, 4>>, <<"PK", 5, 6>>])

  def valid_file?(path, "docx"), do: office_document?(path, ~c"word/document.xml")
  def valid_file?(path, "xlsx"), do: office_document?(path, ~c"xl/workbook.xml")
  def valid_file?(path, "pptx"), do: office_document?(path, ~c"ppt/presentation.xml")

  def valid_file?(path, extension) when is_map_key(@odf_mimetypes, extension),
    do: open_document?(path, Map.fetch!(@odf_mimetypes, extension))

  def valid_file?(path, extension) when is_map_key(@image_types, extension),
    do: image?(path, Map.fetch!(@image_types, extension))

  def valid_file?(path, "svg"), do: safe_svg?(path)

  def valid_file?(path, extension) when extension in ["txt", "md", "csv"],
    do: plain_text?(path)

  def valid_file?(_path, _extension), do: false

  defp header_matches?(path, signatures) do
    case read_header(path, 8) do
      {:ok, header} -> Enum.any?(signatures, &String.starts_with?(header, &1))
      _error -> false
    end
  end

  defp office_document?(path, required_part) do
    with true <- header_matches?(path, [<<"PK", 3, 4>>]),
         {:ok, entries} <- :zip.list_dir(String.to_charlist(path)) do
      Enum.any?(
        entries,
        &match?({:zip_file, ^required_part, _info, _comment, _offset, _size}, &1)
      )
    else
      _not_an_office_archive -> false
    end
  end

  # OpenDocument stores its own type as the archive's `mimetype` entry.
  defp open_document?(path, mimetype) do
    with true <- header_matches?(path, [<<"PK", 3, 4>>]),
         {:ok, [{~c"mimetype", content}]} <-
           :zip.extract(String.to_charlist(path), [{:file_list, [~c"mimetype"]}, :memory]) do
      String.trim(content) == mimetype
    else
      _not_an_open_document -> false
    end
  end

  defp image?(path, mime) do
    case read_header(path, @image_header_bytes) do
      {:ok, header} -> match?({^mime, _width, _height, _variant}, ExImageInfo.info(header))
      _error -> false
    end
  end

  defp safe_svg?(path) do
    with true <- plain_text?(path),
         {:ok, markup} <- File.read(path) do
      String.match?(markup, ~r/<svg[\s>]/i) and not String.match?(markup, @unsafe_svg)
    else
      _not_svg -> false
    end
  end

  defp plain_text?(path) do
    case with_file(path, &no_nul_bytes?/1) do
      {:ok, result} -> result
      {:error, _reason} -> false
    end
  end

  # An empty file is valid text; `:eof` is only reached once every chunk
  # before it came back clean.
  defp no_nul_bytes?(file) do
    case IO.binread(file, @text_chunk_bytes) do
      :eof -> true
      chunk when is_binary(chunk) -> not String.contains?(chunk, <<0>>) and no_nul_bytes?(file)
      {:error, _reason} -> false
    end
  end

  defp read_header(path, byte_count) do
    case with_file(path, &IO.binread(&1, byte_count)) do
      {:ok, data} when is_binary(data) -> {:ok, data}
      {:ok, other} -> {:error, other}
      {:error, reason} -> {:error, reason}
    end
  end

  # Opens `path`, runs `fun` on the handle and always closes it.
  defp with_file(path, fun) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        try do
          {:ok, fun.(file)}
        after
          File.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
