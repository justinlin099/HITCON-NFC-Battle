"""Validate print PNGs and replace the calibrated image in a DOCX template.

Only ``word/media/image1.png`` is replaced.  The surrounding OOXML, including
the floating anchor and its offsets, is copied as opaque bytes.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from io import BytesIO
from typing import Iterable, List, Tuple
import binascii
import copy
import posixpath
import struct
import xml.etree.ElementTree as ET
import zipfile


IMAGE_PART = "word/media/image1.png"
DOCUMENT_PART = "word/document.xml"
DOCUMENT_RELS_PART = "word/_rels/document.xml.rels"
CONTENT_TYPES_PART = "[Content_Types].xml"

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_IHDR_LENGTH = 13
DEFAULT_MAX_PNG_BYTES = 10 * 1024 * 1024
DEFAULT_MAX_PNG_DIMENSION = 20_000
DEFAULT_MAX_PNG_PIXELS = 50_000_000
TEMPLATE_ASPECT_WIDTH = 456
TEMPLATE_ASPECT_HEIGHT = 720
DEFAULT_ASPECT_RATIO = TEMPLATE_ASPECT_WIDTH / TEMPLATE_ASPECT_HEIGHT
# A relative two-percent window accepts the current 1276x2022 artwork while
# still rejecting common paper/photo aspect ratios.
DEFAULT_ASPECT_RATIO_TOLERANCE = 0.02

RELATIONSHIP_NAMESPACES = {
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "http://purl.oclc.org/ooxml/officeDocument/relationships",
}


class DocxTemplateError(Exception):
    """Base class for safe DOCX/PNG validation errors."""


class PngValidationError(DocxTemplateError):
    """The downloaded artwork is not a safe, compatible PNG."""


class TemplateValidationError(DocxTemplateError):
    """The DOCX no longer has the required calibrated structure."""


class DocxBuildError(DocxTemplateError):
    """The validated package could not be rebuilt losslessly by part."""


@dataclass(frozen=True)
class PngMetadata:
    width: int
    height: int
    byte_length: int
    aspect_ratio: float


@dataclass(frozen=True)
class TemplateMetadata:
    image_part: str
    relationship_id: str
    anchor_kind: str
    anchor_width: int
    anchor_height: int
    package_part_count: int

    @property
    def anchor_aspect_ratio(self) -> float:
        return self.anchor_width / self.anchor_height


@dataclass(frozen=True)
class DocxBuildResult:
    document_bytes: bytes
    image: PngMetadata
    template: TemplateMetadata


def validate_png(
    png_bytes: bytes,
    *,
    max_bytes: int = DEFAULT_MAX_PNG_BYTES,
    max_dimension: int = DEFAULT_MAX_PNG_DIMENSION,
    max_pixels: int = DEFAULT_MAX_PNG_PIXELS,
    expected_aspect_ratio: float = DEFAULT_ASPECT_RATIO,
    aspect_ratio_tolerance: float = DEFAULT_ASPECT_RATIO_TOLERANCE,
) -> PngMetadata:
    """Validate PNG signature and IHDR without decoding untrusted pixels."""

    if max_bytes <= 0:
        raise ValueError("max_bytes must be positive")
    if max_dimension <= 0:
        raise ValueError("max_dimension must be positive")
    if max_pixels <= 0:
        raise ValueError("max_pixels must be positive")
    if expected_aspect_ratio <= 0:
        raise ValueError("expected_aspect_ratio must be positive")
    if not 0 <= aspect_ratio_tolerance < 1:
        raise ValueError("aspect_ratio_tolerance must be between 0 and 1")
    if not isinstance(png_bytes, (bytes, bytearray, memoryview)):
        raise PngValidationError("Print artwork must be PNG bytes.")

    data = bytes(png_bytes)
    if len(data) > max_bytes:
        raise PngValidationError("Print artwork exceeds the size limit.")
    if len(data) < 33 or data[:8] != PNG_SIGNATURE:
        raise PngValidationError("Print artwork is not a valid PNG.")

    ihdr_length = struct.unpack(">I", data[8:12])[0]
    chunk_type = data[12:16]
    if ihdr_length != PNG_IHDR_LENGTH or chunk_type != b"IHDR":
        raise PngValidationError("PNG must begin with a 13-byte IHDR chunk.")

    ihdr_data = data[16:29]
    stored_crc = struct.unpack(">I", data[29:33])[0]
    calculated_crc = binascii.crc32(chunk_type + ihdr_data) & 0xFFFFFFFF
    if stored_crc != calculated_crc:
        raise PngValidationError("PNG IHDR checksum is invalid.")

    width, height = struct.unpack(">II", ihdr_data[:8])
    if width <= 0 or height <= 0:
        raise PngValidationError("PNG dimensions must be positive.")
    if width > max_dimension or height > max_dimension:
        raise PngValidationError("PNG dimensions exceed the safety limit.")
    if width * height > max_pixels:
        raise PngValidationError("PNG pixel count exceeds the safety limit.")
    if height <= width:
        raise PngValidationError("Print artwork must use portrait orientation.")

    aspect_ratio = width / height
    relative_difference = abs(aspect_ratio - expected_aspect_ratio) / (
        expected_aspect_ratio
    )
    if relative_difference > aspect_ratio_tolerance:
        raise PngValidationError(
            "Print artwork aspect ratio is incompatible with the template."
        )

    return PngMetadata(
        width=width,
        height=height,
        byte_length=len(data),
        aspect_ratio=aspect_ratio,
    )


def validate_template(template_bytes: bytes) -> TemplateMetadata:
    """Confirm the image part, relation, content type, and unique placement."""

    data = _as_bytes(template_bytes, "DOCX template must be bytes.")
    try:
        with zipfile.ZipFile(BytesIO(data), "r") as package:
            infos = package.infolist()
            names = [info.filename for info in infos]
            duplicates = [
                name for name, count in Counter(names).items() if count > 1
            ]
            if duplicates:
                raise TemplateValidationError(
                    "DOCX template contains duplicate package parts."
                )
            for required in (
                CONTENT_TYPES_PART,
                DOCUMENT_PART,
                DOCUMENT_RELS_PART,
                IMAGE_PART,
            ):
                if required not in names:
                    raise TemplateValidationError(
                        f"DOCX template is missing required part: {required}."
                    )

            content_types_xml = package.read(CONTENT_TYPES_PART)
            relationships_xml = package.read(DOCUMENT_RELS_PART)
            document_xml = package.read(DOCUMENT_PART)
    except TemplateValidationError:
        raise
    except (zipfile.BadZipFile, KeyError, OSError, RuntimeError):
        raise TemplateValidationError("DOCX template package is invalid.") from None

    _validate_png_content_type(content_types_xml)
    relationship_id = _find_image_relationship(relationships_xml)
    anchor_kind, anchor_width, anchor_height = _find_unique_anchor(
        document_xml, relationship_id
    )
    return TemplateMetadata(
        image_part=IMAGE_PART,
        relationship_id=relationship_id,
        anchor_kind=anchor_kind,
        anchor_width=anchor_width,
        anchor_height=anchor_height,
        package_part_count=len(names),
    )


def build_docx(
    template_bytes: bytes,
    png_bytes: bytes,
    *,
    max_png_bytes: int = DEFAULT_MAX_PNG_BYTES,
) -> DocxBuildResult:
    """Replace the calibrated image part and return the rebuilt DOCX bytes."""

    source_bytes = _as_bytes(template_bytes, "DOCX template must be bytes.")
    replacement = _as_bytes(png_bytes, "Print artwork must be PNG bytes.")
    template_metadata = validate_template(source_bytes)
    image_metadata = validate_png(
        replacement,
        max_bytes=max_png_bytes,
        expected_aspect_ratio=template_metadata.anchor_aspect_ratio,
    )

    try:
        with zipfile.ZipFile(BytesIO(source_bytes), "r") as source:
            archive_comment = source.comment
            entries: List[Tuple[zipfile.ZipInfo, bytes]] = [
                (info, source.read(info)) for info in source.infolist()
            ]

        output_buffer = BytesIO()
        with zipfile.ZipFile(output_buffer, "w", allowZip64=True) as output:
            output.comment = archive_comment
            for original_info, original_data in entries:
                info = copy.copy(original_info)
                part_data = (
                    replacement
                    if original_info.filename == IMAGE_PART
                    else original_data
                )
                output.writestr(info, part_data)
        document_bytes = output_buffer.getvalue()
    except (zipfile.BadZipFile, OSError, RuntimeError, ValueError):
        raise DocxBuildError("Could not build the calibrated DOCX.") from None

    _verify_rebuilt_parts(entries, document_bytes, replacement)
    return DocxBuildResult(
        document_bytes=document_bytes,
        image=image_metadata,
        template=template_metadata,
    )


def _validate_png_content_type(xml_bytes: bytes) -> None:
    root = _parse_xml(xml_bytes, CONTENT_TYPES_PART)
    image_override_types: List[str] = []
    png_default_types: List[str] = []
    for element in root.iter():
        local_name = _local_name(element.tag)
        if local_name == "Override":
            part_name = element.attrib.get("PartName", "")
            normalized = "/" + part_name.lstrip("/")
            if normalized == "/" + IMAGE_PART:
                image_override_types.append(element.attrib.get("ContentType", ""))
        elif local_name == "Default":
            if element.attrib.get("Extension", "").lower() == "png":
                png_default_types.append(element.attrib.get("ContentType", ""))

    if image_override_types:
        valid = (
            len(image_override_types) == 1
            and image_override_types[0].lower() == "image/png"
        )
    else:
        valid = (
            len(png_default_types) == 1
            and png_default_types[0].lower() == "image/png"
        )
    if not valid:
        raise TemplateValidationError(
            "DOCX template does not declare image1.png as image/png."
        )


def _find_image_relationship(xml_bytes: bytes) -> str:
    root = _parse_xml(xml_bytes, DOCUMENT_RELS_PART)
    relationship_ids = set()
    image_relationships: List[str] = []
    for element in root.iter():
        if _local_name(element.tag) != "Relationship":
            continue
        relationship_id = element.attrib.get("Id", "")
        if not relationship_id or relationship_id in relationship_ids:
            raise TemplateValidationError(
                "DOCX template relationship IDs must be unique."
            )
        relationship_ids.add(relationship_id)
        if element.attrib.get("TargetMode", "").lower() == "external":
            continue
        target = element.attrib.get("Target", "")
        resolved_target = _resolve_document_relationship_target(target)
        if resolved_target != IMAGE_PART:
            continue
        relationship_type = element.attrib.get("Type", "")
        if not relationship_type.endswith("/image"):
            raise TemplateValidationError(
                "image1.png relationship has the wrong type."
            )
        image_relationships.append(relationship_id)

    if len(image_relationships) != 1:
        raise TemplateValidationError(
            "DOCX template must contain exactly one image1.png relationship."
        )
    return image_relationships[0]


def _resolve_document_relationship_target(target: str) -> str:
    if not target or "\\" in target or ":" in target:
        return ""
    if target.startswith("/"):
        resolved = posixpath.normpath(target.lstrip("/"))
    else:
        resolved = posixpath.normpath(
            posixpath.join(posixpath.dirname(DOCUMENT_PART), target)
        )
    if resolved == ".." or resolved.startswith("../"):
        return ""
    return resolved


def _find_unique_anchor(
    xml_bytes: bytes, relationship_id: str
) -> Tuple[str, int, int]:
    root = _parse_xml(xml_bytes, DOCUMENT_PART)
    total_relationship_references = 0
    placements: List[Tuple[str, ET.Element]] = []

    for element in root.iter():
        for attribute_name, value in element.attrib.items():
            namespace, local_name = _split_qname(attribute_name)
            if (
                namespace in RELATIONSHIP_NAMESPACES
                and local_name in {"embed", "id"}
                and value == relationship_id
            ):
                total_relationship_references += 1

        kind = _local_name(element.tag)
        if kind not in {"anchor", "inline"}:
            continue
        reference_count = 0
        for descendant in element.iter():
            for attribute_name, value in descendant.attrib.items():
                namespace, local_name = _split_qname(attribute_name)
                if (
                    namespace in RELATIONSHIP_NAMESPACES
                    and local_name in {"embed", "id"}
                    and value == relationship_id
                ):
                    reference_count += 1
        if reference_count:
            placements.append((kind, element))

    if total_relationship_references != 1 or len(placements) != 1:
        raise TemplateValidationError(
            "DOCX template must contain exactly one anchor for image1.png."
        )

    anchor_kind, placement = placements[0]
    extent = next(
        (
            child
            for child in list(placement)
            if _local_name(child.tag) == "extent"
        ),
        None,
    )
    if extent is None:
        raise TemplateValidationError("DOCX image anchor has no extent.")
    try:
        width = int(extent.attrib["cx"])
        height = int(extent.attrib["cy"])
    except (KeyError, TypeError, ValueError):
        raise TemplateValidationError("DOCX image anchor extent is invalid.") from None
    if width <= 0 or height <= 0 or height <= width:
        raise TemplateValidationError("DOCX image anchor extent is invalid.")
    return anchor_kind, width, height


def _verify_rebuilt_parts(
    entries: Iterable[Tuple[zipfile.ZipInfo, bytes]],
    document_bytes: bytes,
    replacement: bytes,
) -> None:
    original = {info.filename: data for info, data in entries}
    try:
        with zipfile.ZipFile(BytesIO(document_bytes), "r") as rebuilt:
            rebuilt_names = rebuilt.namelist()
            if rebuilt_names != list(original):
                raise DocxBuildError("DOCX package part order changed.")
            for name, original_data in original.items():
                expected = replacement if name == IMAGE_PART else original_data
                if rebuilt.read(name) != expected:
                    raise DocxBuildError(
                        f"DOCX package part changed unexpectedly: {name}."
                    )
    except DocxBuildError:
        raise
    except (zipfile.BadZipFile, KeyError, OSError, RuntimeError):
        raise DocxBuildError("Could not verify the calibrated DOCX.") from None


def _parse_xml(xml_bytes: bytes, part_name: str) -> ET.Element:
    try:
        return ET.fromstring(xml_bytes)
    except (ET.ParseError, ValueError):
        raise TemplateValidationError(
            f"DOCX template XML is invalid: {part_name}."
        ) from None


def _local_name(name: str) -> str:
    return _split_qname(name)[1]


def _split_qname(name: str) -> Tuple[str, str]:
    if name.startswith("{") and "}" in name:
        namespace, local_name = name[1:].split("}", 1)
        return namespace, local_name
    return "", name


def _as_bytes(value: bytes, message: str) -> bytes:
    if not isinstance(value, (bytes, bytearray, memoryview)):
        error_type = (
            PngValidationError
            if message.startswith("Print artwork")
            else TemplateValidationError
        )
        raise error_type(message)
    return bytes(value)
