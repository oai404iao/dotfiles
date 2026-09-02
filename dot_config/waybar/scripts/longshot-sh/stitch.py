#!/usr/bin/env python3
"""Build a vertical long screenshot from a scrolling screen recording."""

from __future__ import annotations

import os
from pathlib import Path
import sys

import cv2
import numpy as np


MIN_SCROLL = 2
MATCH_CONFIDENCE = 0.5
IGNORE_Y_TOP = 0.15
IGNORE_X = 0.15
SEARCH_WINDOW = 50
MAX_OUTPUT_PIXELS = int(os.environ.get("LONGSHOT_MAX_OUTPUT_PIXELS", "120000000"))


def write_image(path: Path, image: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(
        str(path),
        image,
        [cv2.IMWRITE_PNG_COMPRESSION, 3],
    ):
        raise RuntimeError(f"OpenCV could not write {path}")


def stitch_video(video_path: Path, output_path: Path) -> None:
    if not video_path.is_file():
        raise FileNotFoundError(f"Video not found: {video_path}")

    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video: {video_path}")

    try:
        ok, previous_frame = capture.read()
        if not ok or previous_frame is None:
            raise RuntimeError("Could not read the first video frame")

        frames = [previous_frame]
        anchor_frame = previous_frame.copy()
        height, width, _ = anchor_frame.shape

        x1 = int(width * IGNORE_X)
        x2 = int(width * (1 - IGNORE_X))
        y1 = int(height * IGNORE_Y_TOP)
        template_height = int(height * 0.2)
        last_shift = 0
        total_height = height

        while True:
            ok, current_frame = capture.read()
            if not ok or current_frame is None:
                break

            current_gray = cv2.cvtColor(current_frame, cv2.COLOR_BGR2GRAY)
            anchor_gray = cv2.cvtColor(anchor_frame, cv2.COLOR_BGR2GRAY)

            current_gradient = cv2.Sobel(current_gray, cv2.CV_8U, 0, 1, ksize=3)
            anchor_gradient = cv2.Sobel(anchor_gray, cv2.CV_8U, 0, 1, ksize=3)

            template = current_gradient[
                y1 : y1 + template_height,
                x1:x2,
            ]
            region = anchor_gradient[y1:, x1:x2]
            result = cv2.matchTemplate(region, template, cv2.TM_CCOEFF_NORMED)

            if last_shift > 0:
                mask = np.zeros_like(result)
                y_min = max(0, last_shift - SEARCH_WINDOW)
                y_max = min(result.shape[0], last_shift + SEARCH_WINDOW)
                mask[y_min:y_max, :] = 1
                result = np.multiply(result, mask)

            _, confidence, _, location = cv2.minMaxLoc(result)
            shift = location[1]

            if (
                confidence > MATCH_CONFIDENCE
                and MIN_SCROLL < shift < region.shape[0] - 5
            ):
                new_content_y = height - shift
                new_part = current_frame[new_content_y:, :, :]
                if new_part.size == 0:
                    continue

                total_height += new_part.shape[0]
                if total_height * width > MAX_OUTPUT_PIXELS:
                    raise RuntimeError(
                        "Long screenshot exceeds LONGSHOT_MAX_OUTPUT_PIXELS "
                        f"({MAX_OUTPUT_PIXELS})"
                    )

                frames.append(new_part)
                anchor_frame = current_frame.copy()
                if last_shift == 0:
                    last_shift = shift
                else:
                    last_shift = int(last_shift * 0.6 + shift * 0.4)

        if len(frames) == 1:
            print("No scrolling detected; saving the first frame")
            write_image(output_path, frames[0])
            return

        write_image(output_path, np.vstack(frames))
        print(f"Saved {output_path}")
    finally:
        capture.release()


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(
            "Usage: stitch.py <input_video> <output_image>",
            file=sys.stderr,
        )
        return 2

    try:
        stitch_video(Path(argv[1]), Path(argv[2]))
    except Exception as error:
        print(f"Longshot stitching failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
