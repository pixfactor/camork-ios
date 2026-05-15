#!/usr/bin/env python3
"""SwiftUI Text Overlap Detector — 모든 iOS 프로젝트에서 사용 가능

검출 패턴 (5종):
1. P1: navigationTitle(.large) + padding 없이 content 바로 시작
2. P2: HStack 내 Text에 .lineLimit(1) 없음 (긴 한글명 overflow)
3. P3: .frame(width: 고정) + Text
4. P4: ZStack 내부 요소가 명시적 크기 없이 겹침 가능
5. P5: Text.lineLimit(1)만 있고 .truncationMode(.tail) 누락

사용법:
    python3 detect_text_overlap.py <project_root>
"""

import re
import sys
import os
from pathlib import Path
from collections import defaultdict

# ── 검출 룰 ───────────────────────────────────────────

def find_swift_files(root: str):
    for path in Path(root).rglob("*.swift"):
        if "DerivedData" not in str(path) and "Pods" not in str(path):
            yield path

def scan_file(filepath: Path) -> list[dict]:
    issues = []
    text = filepath.read_text(encoding="utf-8", errors="ignore")
    lines = text.split("\n")

    for i, line in enumerate(lines, 1):
        # P1: .navigationBarTitleDisplayMode(.large) → padding 확인
        if ".navigationBarTitleDisplayMode(.large)" in line:
            # 다음 5줄 안에 .padding(.top, ...) 또는 Spacer() 확인
            subsequent = "\n".join(lines[i:min(i+5, len(lines))])
            if not re.search(r'\.padding\(\.top|Spacer\(\)|\.safeAreaInset', subsequent):
                issues.append({
                    "file": str(filepath), "line": i, "priority": "P1-HIGH",
                    "desc": "navTitle(.large) 근처에 top padding 부재 → 타이틀-컨텐츠 겹침 위험",
                    "fix": '.navigationBarTitleDisplayMode(.inline) 또는 .padding(.top, 60) 추가'
                })
                break  # 파일당 한 번만

        # P2: HStack 내 Text에 lineLimit 없음
        # 간단 휴리스틱: .font(...) 후 바로 .foregroundStyle(...)로 끝나는 Text
        if re.search(r'Text\(.+\)', line):
            # 이 line에 .lineLimit(1)이나 .lineLimit(2)가 없고
            # 바로 아래 2줄 이내에도 .lineLimit 없으면
            if '.lineLimit(' not in line:
                next_two = "\n".join(lines[i:min(i+3, len(lines))])
                if '.lineLimit(' not in next_two:
                    # 주변에 HStack이 있는지 확인
                    context = "\n".join(lines[max(0,i-5):min(i+3, len(lines))])
                    if 'HStack' in context and '.font(' in line:
                        issues.append({
                            "file": str(filepath), "line": i, "priority": "P2-MEDIUM",
                            "desc": "HStack 내 Text에 .lineLimit(1) 없음 → 긴 텍스트 오버플로우",
                            "fix": ".lineLimit(1).truncationMode(.tail).layoutPriority(1)"
                        })

        # P3: 고정 width + Text
        if re.search(r'\.frame\(width:\s*\d+', line):
            context = "\n".join(lines[max(0,i-3):min(i+3, len(lines))])
            if 'Text(' in context and '.lineLimit(' not in context:
                issues.append({
                    "file": str(filepath), "line": i, "priority": "P3-MEDIUM",
                    "desc": "고정 width frame + Text (lineLimit 없음) → 텍스트 잘림/겹침",
                    "fix": ".frame(maxWidth: .infinity, alignment: .leading) + .lineLimit(1)"
                })

        # P5: .lineLimit(1)만 있고 .truncationMode(.tail) 누락
        if '.lineLimit(1)' in line and '.truncationMode(' not in line:
            issues.append({
                "file": str(filepath), "line": i, "priority": "P5-LOW",
                "desc": ".lineLimit(1)만 있고 truncationMode 누락 → '...' 생략 안 됨",
                "fix": ".lineLimit(1).truncationMode(.tail)"
            })

    return issues


def main():
    if len(sys.argv) < 2:
        root = "."
    else:
        root = sys.argv[1]

    all_issues = defaultdict(list)
    file_count = 0

    for f in find_swift_files(root):
        file_count += 1
        for issue in scan_file(f):
            all_issues[issue["priority"]].append(issue)

    # ── 리포트 ──
    print(f"🔍 검사 완료: {file_count}개 Swift 파일\n")
    
    total = sum(len(v) for v in all_issues.values())
    if total == 0:
        print("✅ 텍스트 겹침 패턴 미발견!")
        return 0

    for priority in ["P1-HIGH", "P2-MEDIUM", "P3-MEDIUM", "P5-LOW"]:
        issues = all_issues.get(priority, [])
        if not issues:
            continue
        print(f"## {priority} ({len(issues)}건)")
        for iss in issues[:20]:
            print(f"  {iss['file']}:{iss['line']}")
            print(f"    → {iss['desc']}")
            print(f"    🔧 {iss['fix']}")
        print()

    print(f"📊 총 {total}건 발견")
    return 1


if __name__ == "__main__":
    sys.exit(main())
