#!/usr/bin/env python3
"""Fail CI if native annotation validation omits required coverage."""
import json
import sys


def validate(report):
    assert report["syntheticFixture"] is True
    annotations = report["annotations"]
    for key in (
        "portableProject", "preparationCancellation", "existingDestinationPreserved",
        "exporterReuse", "sourceAssetsUnchanged", "temporaryOutputsCleaned",
    ):
        assert annotations[key] is True, key
    exports = annotations["exports"]
    assert len(exports) == 2
    assert {(item["width"], item["height"]) for item in exports} == {(1920, 1080), (3840, 2160)}
    for item in exports:
        assert 5.5 < item["duration"] < 7
        assert 0 <= item["previewExportMeanDifference"] < 8
    assert annotations["fourKFrameSize"] == [3840, 2160]
    hold = annotations["hold"]
    assert hold["outputStart"] < hold["sampledOutput"] < hold["outputEnd"]
    assert annotations["blurInsideDifference"] > 4
    assert 0 <= annotations["blurOutsideDifference"] < 0.001
    assert annotations["beforeMeanDifference"] < 0.08
    assert annotations["afterMeanDifference"] < 0.08


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as source:
        validate(json.load(source))
    print("PASS required synthetic annotation report coverage")
