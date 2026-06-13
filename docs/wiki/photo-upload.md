---
title: Photo Upload
slug: photo-upload
topic: photo-upload
summary: Photo upload is implemented now rather than deferred to a future update
tags:
  - capture
volatility: warm
confidence: medium
created: 2026-05-13
updated: 2026-06-13
verified: 2026-05-13
compiled-from: conversation
sources:
  - session:31314bf9-84f5-4c58-b2e7-b4d8aed0bf26
  - session:c43d5e77-d667-4e71-a574-47aaab5b6a7a
  - session:c33b9adb-9d1a-4717-9314-b45a61e6cbc3
  - session:c1691db0-d63e-4062-adad-1cfa0d679d09
---

# Photo Upload

## Overview

Photo upload is implemented now rather than deferred to a future update. <!-- [^31314-1] -->

## Upload Service

Upload now goes through nmp.blossom.upload via dispatchSilent + ActionResultRegistry await, with zero signing/URLSession in Swift (D13/D0 compliant). The previous BlossomUploader.swift file and all its references have been deleted.

<!-- citations: [^c1691-227] -->
## Photo Selection

ChangePhotoSheet uses a PhotosPicker row for library photo selection only; camera capture is excluded as a separate brief per advisor recommendation. Selected photos are resized to 800px JPEG at quality 0.85 using UIGraphicsImageRenderer before upload. <!-- [^31314-3] -->

## Upload Completion

Upon successful upload, the returned URL is written back into the pictureURL binding and the sheet is dismissed. <!-- [^31314-4] -->

## UI States

ChangePhotoSheet surfaces inline loading and error states during the upload process. If no signer is available, ChangePhotoSheet displays a 'Sign in to upload a photo.' message instead of the upload flow. <!-- [^31314-5] -->

## Out of Scope

Camera capture, multiple-host fallback, a 'remove photo' affordance, video uploads, and persisting the photo locally as a cache are out of scope.

<!-- citations: [^31314-6] [^c43d5-12] [^c33b9-6] -->
