# REQ-001: Composer Attachments

## Overview

PiNative supports composer attachments through the same simple workflows users expect
from a native macOS chat composer: paste, drag/drop, and the composer `+` picker.

Images are sent to Pi as RPC image attachments. Readable regular files that are not
classified as images are sent as local file references rather than hidden file-content
inserts. This keeps attachment behavior predictable and avoids unexpectedly consuming
prompt context with large or binary file contents.

## Requirements

### REQ-001.1: Image attachment workflows

1. A user MUST be able to paste an image into the composer, see it appear as an attachment chip, and send it as an image attachment. [manual]
2. A user MUST be able to drag an image file onto the composer, see it appear as an attachment chip, and send it as an image attachment. [manual]
3. A user MUST be able to click the composer `+` control, select an image file, see it appear as an attachment chip, and send it as an image attachment. [manual]

### REQ-001.2: File attachment workflows

1. A user MUST be able to paste a readable regular file from Finder into the composer, see it appear as a file attachment chip, and send it as a file reference. [manual]
2. A user MUST be able to drag a readable regular file onto the composer, see it appear as a file attachment chip, and send it as a file reference. [manual]
3. A user MUST be able to click the composer `+` control, select a readable regular file, see it appear as a file attachment chip, and send it as a file reference. [manual]

### REQ-001.3: Attachment prompt behavior

1. Image attachments MUST be prepared for the Pi RPC `prompt` command as image payloads with MIME type and base64 data.
2. File-reference attachments MUST be prepared as an `Attached files:` prompt block listing local paths plus either user message text or the fixed attachment-only instruction, with no additional file-content preview text.
3. A draft with one or more attachments and no typed text MUST produce a prepared prompt.
4. A draft with no typed text and no attachments MUST NOT produce a sendable prompt.

### REQ-001.4: Attachment classification and safety

1. Pasted bitmap image data with no file URL MUST be classified as an image attachment.
2. PNG, JPG, and JPEG image file URLs MUST be classified as image attachments.
3. Representative readable regular file URLs that are not classified as images, including PDF, text, binary, and extensionless files, MUST be classified as file-reference attachments.
4. Missing files MUST produce an attachment error instead of an attachment.
5. File-reference attachments MUST NOT add image payloads to the RPC prompt.

## Non-goals

- This spec does not require exhaustive automated coverage of every image or non-image file type. Tests use PNG/JPEG as representative image fixtures and PDF/text/binary/extensionless files as representative non-image regular file fixtures while the product workflow requirement remains broader.
- This spec does not require separate 2119 requirements for every chip styling detail, transcript styling detail, or internal RPC field detail.
- Multiple-selection picker behavior, remove controls, accessibility labels, and transcript polish remain product expectations, but they are intentionally not separate enforced requirements in this first attachment spec.
