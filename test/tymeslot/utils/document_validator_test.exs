defmodule Tymeslot.Utils.DocumentValidatorTest do
  use ExUnit.Case, async: true

  @moduletag :utils
  @moduletag :unit

  alias Tymeslot.Utils.DocumentValidator

  setup do
    dir = Path.join(System.tmp_dir!(), "document_validator_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  defp write(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  defp zip(entries) do
    {:ok, {_name, bytes}} =
      :zip.create(~c"archive.zip", Enum.map(entries, fn {n, c} -> {~c"#{n}", c} end), [:memory])

    bytes
  end

  describe "pdf" do
    test "accepts a file starting with the PDF signature", %{dir: dir} do
      assert DocumentValidator.valid_file?(write(dir, "a.pdf", "%PDF-1.7\n..."), "pdf")
    end

    test "rejects an executable renamed to .pdf", %{dir: dir} do
      refute DocumentValidator.valid_file?(write(dir, "a.pdf", "MZ\x90\x00binary"), "pdf")
    end
  end

  describe "zip" do
    test "accepts a real archive", %{dir: dir} do
      assert DocumentValidator.valid_file?(write(dir, "a.zip", zip([{"x.txt", "x"}])), "zip")
    end

    test "rejects text renamed to .zip", %{dir: dir} do
      refute DocumentValidator.valid_file?(write(dir, "a.zip", "not an archive"), "zip")
    end
  end

  describe "docx / xlsx" do
    test "accepts a Word document", %{dir: dir} do
      path = write(dir, "a.docx", zip([{"word/document.xml", "<w/>"}]))
      assert DocumentValidator.valid_file?(path, "docx")
    end

    test "accepts an Excel workbook", %{dir: dir} do
      path = write(dir, "a.xlsx", zip([{"xl/workbook.xml", "<x/>"}]))
      assert DocumentValidator.valid_file?(path, "xlsx")
    end

    test "rejects an ordinary zip renamed to .docx", %{dir: dir} do
      path = write(dir, "a.docx", zip([{"payload.exe", "MZ"}]))
      refute DocumentValidator.valid_file?(path, "docx")
    end

    test "rejects a workbook renamed to .docx", %{dir: dir} do
      path = write(dir, "a.docx", zip([{"xl/workbook.xml", "<x/>"}]))
      refute DocumentValidator.valid_file?(path, "docx")
    end
  end

  describe "txt / md" do
    test "accepts UTF-8 and legacy single-byte text", %{dir: dir} do
      assert DocumentValidator.valid_file?(write(dir, "a.txt", "Příliš žluťoučký kůň"), "txt")
      assert DocumentValidator.valid_file?(write(dir, "b.md", <<"# Nadpis ", 0xE8, "\n">>), "md")
    end

    test "accepts an empty file", %{dir: dir} do
      assert DocumentValidator.valid_file?(write(dir, "a.txt", ""), "txt")
    end

    test "rejects binary content", %{dir: dir} do
      refute DocumentValidator.valid_file?(write(dir, "a.txt", <<"MZ", 0, 0, 1>>), "txt")
    end
  end

  describe "pptx / odt / ods" do
    test "accepts a PowerPoint presentation", %{dir: dir} do
      path = write(dir, "a.pptx", zip([{"ppt/presentation.xml", "<p/>"}]))
      assert DocumentValidator.valid_file?(path, "pptx")
    end

    test "accepts OpenDocument text and spreadsheet by their mimetype entry", %{dir: dir} do
      odt =
        write(dir, "a.odt", zip([{"mimetype", "application/vnd.oasis.opendocument.text"}]))

      ods =
        write(dir, "a.ods", zip([{"mimetype", "application/vnd.oasis.opendocument.spreadsheet"}]))

      assert DocumentValidator.valid_file?(odt, "odt")
      assert DocumentValidator.valid_file?(ods, "ods")
      refute DocumentValidator.valid_file?(ods, "odt")
    end

    test "rejects a zip without the OpenDocument mimetype", %{dir: dir} do
      refute DocumentValidator.valid_file?(write(dir, "a.odt", zip([{"x", "y"}])), "odt")
    end
  end

  describe "images" do
    # A 1x1 PNG.
    @png Base.decode64!(
           "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
         )

    test "accepts a PNG as .png and rejects it as .jpg", %{dir: dir} do
      path = write(dir, "a.png", @png)
      assert DocumentValidator.valid_file?(path, "png")
      refute DocumentValidator.valid_file?(path, "jpg")
    end

    test "accepts a JPEG as .jpg and .jpeg", %{dir: dir} do
      jpeg =
        <<0xFF, 0xD8, 0xFF, 0xE0, 0, 16, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xFF, 0xC0, 0, 11,
          8, 0, 1, 0, 1, 1, 1, 17, 0, 0xFF, 0xD9>>

      path = write(dir, "a.jpg", jpeg)
      assert DocumentValidator.valid_file?(path, "jpg")
      assert DocumentValidator.valid_file?(path, "jpeg")
    end

    test "rejects text renamed to an image", %{dir: dir} do
      refute DocumentValidator.valid_file?(write(dir, "a.webp", "not an image"), "webp")
    end
  end

  describe "svg" do
    test "accepts plain SVG markup", %{dir: dir} do
      svg = ~s(<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>)
      assert DocumentValidator.valid_file?(write(dir, "a.svg", svg), "svg")
    end

    test "rejects scripts, event handlers, javascript: links and entities", %{dir: dir} do
      for markup <- [
            ~s|<svg><script>alert(1)</script></svg>|,
            ~s|<svg onload="alert(1)"></svg>|,
            ~s|<svg><a href="javascript:alert(1)">x</a></svg>|,
            ~s|<svg><foreignObject><iframe/></foreignObject></svg>|,
            ~s|<!DOCTYPE svg [<!ENTITY x "y">]><svg></svg>|
          ] do
        refute DocumentValidator.valid_file?(write(dir, "a.svg", markup), "svg"), markup
      end
    end

    test "rejects a file that is not SVG", %{dir: dir} do
      refute DocumentValidator.valid_file?(write(dir, "a.svg", "hello"), "svg")
    end
  end

  test "accepts CSV as plain text", %{dir: dir} do
    assert DocumentValidator.valid_file?(write(dir, "a.csv", "jméno;částka\nJan;100\n"), "csv")
  end

  test "rejects any other extension and a missing file", %{dir: dir} do
    refute DocumentValidator.valid_file?(write(dir, "a.exe", "%PDF-"), "exe")
    refute DocumentValidator.valid_file?(Path.join(dir, "missing.pdf"), "pdf")
  end
end
