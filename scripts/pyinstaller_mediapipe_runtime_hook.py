"""Runtime shims for the packaged pose worker.

MediaPipe imports drawing helpers from its package initializers. Those helpers
depend on OpenCV and matplotlib, but CamiFit only uses the Tasks pose
landmarker and never calls the drawing helpers. Stubbing the drawing-only
imports keeps the distributable small enough for free download hosting while
preserving the inference path.
"""

from __future__ import annotations

import sys
import types


class _OptionalDrawingModule(types.ModuleType):
    def __getattr__(self, name: str):
        def _not_available(*_args, **_kwargs):
            raise RuntimeError(
                f"{self.__name__}.{name} is unavailable in the packaged pose worker"
            )

        return _not_available


if "cv2" not in sys.modules:
    sys.modules["cv2"] = _OptionalDrawingModule("cv2")

if "matplotlib" not in sys.modules:
    matplotlib = types.ModuleType("matplotlib")
    matplotlib.__path__ = []
    sys.modules["matplotlib"] = matplotlib

if "matplotlib.pyplot" not in sys.modules:
    pyplot = _OptionalDrawingModule("matplotlib.pyplot")
    sys.modules["matplotlib.pyplot"] = pyplot
