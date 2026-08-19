from __future__ import annotations

import binascii
from io import BytesIO
import struct
import unittest
import zipfile

from app.docx_template import (
    CONTENT_TYPES_PART,
    DOCUMENT_PART,
    DOCUMENT_RELS_PART,
    IMAGE_PART,
    PngValidationError,
    TemplateValidationError,
    build_docx,
    validate_png,
    validate_template,
)


def png_bytes(width=1276, height=2022, *, corrupt_crc=False, padding=b""):
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    crc = binascii.crc32(b"IHDR" + ihdr_data) & 0xFFFFFFFF
    if corrupt_crc:
        crc ^= 0xFFFFFFFF
    ihdr = struct.pack(">I", len(ihdr_data)) + b"IHDR" + ihdr_data
    ihdr += struct.pack(">I", crc)
    iend_crc = binascii.crc32(b"IEND") & 0xFFFFFFFF
    iend = struct.pack(">I", 0) + b"IEND" + struct.pack(">I", iend_crc)
    return signature + ihdr + padding + iend


CONTENT_TYPES_XML = b"""<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>"""

DOCUMENT_RELS_XML = b"""<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId6" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
</Relationships>"""

DOCUMENT_XML = b"""<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
 xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
 xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
 <w:body><w:p><w:r><w:drawing>
  <wp:anchor behindDoc="1"><wp:extent cx="456" cy="720"/>
   <a:graphic><a:blip r:embed="rId6"/></a:graphic>
  </wp:anchor>
 </w:drawing></w:r></w:p></w:body>
</w:document>"""


def docx_fixture(
    *,
    content_types=CONTENT_TYPES_XML,
    document=DOCUMENT_XML,
    relationships=DOCUMENT_RELS_XML,
    include_image=True,
):
    output = BytesIO()
    with zipfile.ZipFile(output, "w") as package:
        package.comment = b"fixture-comment"
        package.writestr(CONTENT_TYPES_PART, content_types, zipfile.ZIP_DEFLATED)
        package.writestr("_rels/.rels", b"ROOT-RELS", zipfile.ZIP_STORED)
        package.writestr(DOCUMENT_PART, document, zipfile.ZIP_DEFLATED)
        package.writestr(
            DOCUMENT_RELS_PART, relationships, zipfile.ZIP_DEFLATED
        )
        package.writestr("word/styles.xml", b"\x00opaque-style-bytes\xff")
        if include_image:
            package.writestr(IMAGE_PART, png_bytes(456, 720), zipfile.ZIP_STORED)
    return output.getvalue()


class PngValidationTests(unittest.TestCase):
    def test_accepts_current_app_dimensions(self):
        metadata = validate_png(png_bytes(1276, 2022))
        self.assertEqual((metadata.width, metadata.height), (1276, 2022))
        self.assertEqual(metadata.byte_length, len(png_bytes(1276, 2022)))

    def test_rejects_invalid_signature_or_ihdr_crc(self):
        with self.assertRaises(PngValidationError):
            validate_png(b"not-a-png")
        with self.assertRaises(PngValidationError):
            validate_png(png_bytes(corrupt_crc=True))

    def test_rejects_landscape_and_wrong_aspect_ratio(self):
        with self.assertRaises(PngValidationError):
            validate_png(png_bytes(2022, 1276))
        with self.assertRaises(PngValidationError):
            validate_png(png_bytes(1000, 1001))

    def test_rejects_png_over_size_limit(self):
        image = png_bytes(padding=b"x" * 64)
        with self.assertRaises(PngValidationError):
            validate_png(image, max_bytes=len(image) - 1)

    def test_rejects_oversized_ihdr_dimensions_and_pixel_count(self):
        # These headers remain only a few bytes long, so the compressed byte
        # cap alone cannot prevent a decoder allocation DoS.
        with self.assertRaises(PngValidationError):
            validate_png(png_bytes(20_001, 31_580))
        with self.assertRaises(PngValidationError):
            validate_png(
                png_bytes(7_100, 11_210),
                max_dimension=20_000,
                max_pixels=50_000_000,
            )


class TemplateValidationTests(unittest.TestCase):
    def test_validates_part_relation_content_type_and_anchor(self):
        metadata = validate_template(docx_fixture())
        self.assertEqual(metadata.image_part, IMAGE_PART)
        self.assertEqual(metadata.relationship_id, "rId6")
        self.assertEqual(metadata.anchor_kind, "anchor")
        self.assertEqual((metadata.anchor_width, metadata.anchor_height), (456, 720))
        self.assertEqual(metadata.package_part_count, 6)

    def test_rejects_missing_image_part(self):
        with self.assertRaises(TemplateValidationError):
            validate_template(docx_fixture(include_image=False))

    def test_rejects_wrong_content_type(self):
        wrong = CONTENT_TYPES_XML.replace(b"image/png", b"image/jpeg")
        with self.assertRaises(TemplateValidationError):
            validate_template(docx_fixture(content_types=wrong))

    def test_rejects_missing_image_relationship(self):
        wrong = DOCUMENT_RELS_XML.replace(b"media/image1.png", b"media/other.png")
        with self.assertRaises(TemplateValidationError):
            validate_template(docx_fixture(relationships=wrong))

    def test_rejects_duplicate_anchor_reference(self):
        second = b"""<wp:anchor><wp:extent cx="456" cy="720"/>
          <a:blip r:embed="rId6"/></wp:anchor>"""
        wrong = DOCUMENT_XML.replace(b"</w:drawing>", second + b"</w:drawing>")
        with self.assertRaises(TemplateValidationError):
            validate_template(docx_fixture(document=wrong))


class BuilderTests(unittest.TestCase):
    def test_uses_the_callers_png_byte_limit(self):
        source = docx_fixture()
        replacement = png_bytes(1276, 2022, padding=b"replacement-pixels")

        with self.assertRaises(PngValidationError):
            build_docx(
                source,
                replacement,
                max_png_bytes=len(replacement) - 1,
            )

        result = build_docx(
            source,
            replacement,
            max_png_bytes=len(replacement),
        )
        self.assertEqual(result.image.byte_length, len(replacement))

    def test_replaces_only_image_part_and_returns_metadata(self):
        source = docx_fixture()
        replacement = png_bytes(1276, 2022, padding=b"replacement-pixels")

        result = build_docx(source, replacement)

        self.assertEqual((result.image.width, result.image.height), (1276, 2022))
        self.assertEqual(result.template.relationship_id, "rId6")
        with zipfile.ZipFile(BytesIO(source), "r") as original_package:
            original_names = original_package.namelist()
            original_parts = {
                name: original_package.read(name) for name in original_names
            }
            original_comment = original_package.comment
        with zipfile.ZipFile(BytesIO(result.document_bytes), "r") as built:
            self.assertEqual(built.namelist(), original_names)
            self.assertEqual(built.comment, original_comment)
            self.assertEqual(built.read(IMAGE_PART), replacement)
            for name, content in original_parts.items():
                if name != IMAGE_PART:
                    self.assertEqual(
                        built.read(name),
                        content,
                        "uncompressed package part changed: " + name,
                    )
            self.assertEqual(built.read(DOCUMENT_PART), DOCUMENT_XML)
            self.assertEqual(
                built.read(DOCUMENT_RELS_PART), DOCUMENT_RELS_XML
            )


if __name__ == "__main__":
    unittest.main()
