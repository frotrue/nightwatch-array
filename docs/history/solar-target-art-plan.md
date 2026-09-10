# 최종 결정 · 2026-09-11

사용자가 각진 소행성·밝은 얼음 결정면·줄무늬 구체의 이미지를 다시 제시하고,
“첨부 이미지 느낌으로 수정”을 선택했다. 이에 아래 광학 외피 계획은 채택하지 않는다.
시험 적용한 광막·과노출 패치를 걷어내고 기존 패싯 렌더러를 유지했다.
게임 수치, 관측 판정, 저장 키에는 변경이 없다.

실제 게임 크기 비교와 한국어/영어 연구 화면 9장을 다시 캡처했다.
Windows 내보내기까지 21개 검사를 통과했다. 같은 버전의 엔진에서 내보낸 EXE의 리소스를
읽어 `--live-sky` 진단을 실행했고, 초기 24개 표적의 이동 장면 2장을 확인했다.
이 진단은 저장 파일을 건드리지 않으며 실제 조작감·성능 검증을 대신하지 않는다.
현행 외형은 [디자인 상세](../design-details.md)의 소행성·얼음 소행성·행성 절을 따른다.
아래는 검토한 원문이며 현재 구현 지시가 아니다.

---

# 소행성·얼음 소행성·행성 외형 교체 (방향 A · 광학 외피)

`scripts/meteor.gd`의 `_draw_asteroid_head` / `_draw_planet_head`를 버리고, 세 본체를
유성과 같은 어휘로 다시 그린다. 목업은 승인됐다. 새 드로잉 원시함수는 만들지 않는다 —
`_ellipse_points`, `_draw_graded_polygon`, `draw_multiline` 세 개로 전부 그린다.

## 왜 바꾸나

지금 세 본체는 서로도 안 맞고 유성과도 남남이다. 소행성 둘에만 `draw_polyline` 외곽선이
있는데 유성에는 파일 전체에 외곽선이 없다. 행성은 576분할 그라데이션, 소행성은 평면 패싯,
유성은 부채꼴로 흩어지는 유기 폴리곤이다. 얼음의 밝은 면은 `index % 3 == 0`이라 조명과
무관하다.

## 따를 규칙 (유성에서 그대로 가져온다)

- 외곽선 없음. 가장자리는 `_draw_graded_polygon`의 부채꼴로 흩어져 끝난다.
- 층 순서와 알파: 광학 스커트 → 광막 → 몸통 → 과노출 패치.
- 밝은 점은 중심이 아니라 광원 쪽으로 치우친다.
- 표면 자국은 `draw_multiline` 2패스뿐이다 (넓고 흐린 glow + 좁고 밝은 primary).
- 실루엣은 `_ellipse_points`(16점 + sin 왜곡). 종류마다 왜곡량만 다르다.

일부러 어긋나는 곳은 하나다: **몸통은 가산 합성이 아니라 불투명하다.** 배경 별을 가려야
하기 때문이다. 그래서 알파가 아니라 색으로 감쇠시킨다.

## 값

```gdscript
const LIGHT := Vector2(-0.55, -0.72).normalized()   # 세 본체 공통
var axis := LIGHT.rotated(1.1)
var bright := LIGHT * r * 0.55                      # r = 지금 _draw_type_silhouette에 넘어오는 radius
```

| 대상 | type_id | 왜곡량 | 과노출 패치 (x, y) |
|---|---|---|---|
| 소행성 | `variable_star` | 0.30 | 0.20 r, 0.12 r |
| 얼음 소행성 | `binary_star` | 0.20 | 0.34 r, 0.20 r |
| 행성 | `galaxy` | 0.03 | 0.44 r, 0.26 r |

그리는 순서. `V`는 `visibility`.

1. **광학 스커트** — `_ellipse_points(axis, r * 2.0, r * 2.0, Vector2.ZERO, 왜곡량)`을
   `_draw_graded_polygon(pts, bright, Color(glow_color, 0.10 * V), Color(glow_color, 0.0))`
2. **광막** — 같은 방식, 반경 `r * 1.30`, 중심색 `Color(glow_color, 0.26 * V)`
3. **몸통 (불투명)** — `_ellipse_points(axis, r, r, Vector2.ZERO, 왜곡량)`을
   `_draw_graded_polygon(pts, bright, Color(primary_color.lerp(Color.WHITE, 0.14), V), Color(primary_color.darkened(0.83), V))`
4. **과노출 패치** — `centre := LIGHT * r * 0.34`,
   `_ellipse_points(LIGHT.rotated(0.3), r * hot.x, r * hot.y, centre, 0.18)`을
   `_draw_graded_polygon(pts, centre, Color(primary_color.lerp(Color.WHITE, 0.76), 0.92 * V), Color(primary_color.lerp(Color.WHITE, 0.20), 0.0))`
5. **표면 자국** — `draw_multiline` 2패스.
   `Color(glow_color, 0.25 * V)` 굵기 `maxf(0.72, r * 0.055)`,
   그 위에 `Color(primary_color, 0.58 * V)` 굵기 `maxf(0.44, r * 0.021)`.

자국 좌표는 전부 `r` 단위다.

- **소행성** — 크레이터 5개 `(x, y, 반경)`: `(-0.34, -0.26, 0.21)` `(0.28, 0.12, 0.26)`
  `(-0.10, 0.44, 0.15)` `(0.44, -0.34, 0.13)` `(-0.52, 0.16, 0.12)`.
  크레이터마다 시작각 `atan2(-LIGHT.y, -LIGHT.x) - 0.9`에서 `0.62`씩 3번, 매번 길이
  `0.52 rad`인 현의 두 끝점을 선분으로 넣는다. 그늘진 안쪽 벽만 그려지는 셈이다.
- **얼음 소행성** — 균열 3줄. 좌표에 `r * 0.92`를 곱하고 연속 두 점씩 선분으로 넣는다.
  `(-0.70,-0.16) (-0.30,-0.30) (0.04,-0.04) (0.38,0.12) (0.60,0.42)` /
  `(-0.24,0.64) (-0.08,0.26) (0.16,0.00) (0.22,-0.42)` /
  `(0.30,-0.60) (0.44,-0.22) (0.68,0.00)`
- **행성** — 위도 띠 5줄, `sl = -0.62, -0.34, -0.02, 0.28, 0.58`.
  `w = r * sqrt(1 - sl * sl) * 0.82`, `y = r * sl`, `bulge = w * 0.15`,
  `점(t) = Vector2(-w + 2.0 * w * t, y + bulge * (1.0 - pow(2.0 * t - 1.0, 2.0)))`.
  `t`를 6등분해 `k = 2`만 빼고 5개 대시: 시작 `k / 6.0 + 0.02`, 끝 `(k + 1) / 6.0 - 0.02`.
  고리나 궤도선은 만들지 않는다.

## 결정해야 할 것 하나

한 CanvasItem은 블렌드 모드가 하나인데, 몸통은 불투명이어야 하고 스커트·광막은 가산이어야
유성과 같이 읽힌다.

- 권장: 자식 `Node2D`에 `SHARED_ADDITIVE_MATERIAL`을 주고 `show_behind_parent = true`로
  둬서 1·2단계만 그린다. 3~5단계는 지금처럼 부모(`material = null`)가 그린다.
- 간단히 가려면 부모에서 알파 합성으로 다 그려도 된다. 하늘이 거의 검정이라 색은 사실상
  같고, 차이는 헤일로 안의 배경 별이 약해지는 것뿐이다.

어느 쪽으로 갔는지 결과에 적는다.

## 유지할 것

- `is_solid_body()`, `get_observation_body_radius()`, 추적 반경, 관측 판정, 보상,
  출현 확률, 이동, 회차 수명, 분광 대역
- 저장·연구 ID (`variable_star` / `binary_star` / `galaxy`)와 표시 이름
- 세 본체에 꼬리 없음, 대상별 자동 관측 원 없음
- `get_burn_visibility()`와 linger 알파 처리
- 성도의 실제 별·M31 표식

## 지울 것

`_draw_asteroid_head`, `_draw_planet_head` 전체. 평면 패싯, 채워진 크레이터 원
`#292724`, 손으로 박은 균열 좌표, 576분할 띠, `draw_polyline` 외곽선, `0.8π~1.7π` 호,
`1.04r` 헤일로가 여기 다 들어 있다.

## 검증

- `.\tools\validate.ps1 -GodotPath $godot -Build`
- `tests/solar_target_review.gd` 캡처를 다시 떠서 **실제 크기**(36.12 / 40.32 / 53.76px)로
  셋이 구분되는지, 유성과 한 세트로 읽히는지 본다. 큰 그림만 보고 판정하지 않는다.
- 실제 빌드에서 하늘을 한 번 본다. 밀도 높은 순간에 광막이 유성과 섞여 헷갈리는지가 관건이다.

## 문서

- `docs/design.md`에 날짜 승인 한 줄.
- `docs/design-details.md`의 `소행성·얼음 소행성·행성 (2026-09-11)` 절에 새 값 반영.
  이 절의 "세 본체에는 발광 꼬리와 대상별 자동 관측 원을 그리지 않는다"는 그대로 두되,
  **광학 스커트·광막은 예외로 명시해야 한다.** 지금 문장과 충돌한다.
- 끝나면 이 파일을 `docs/history/`로 옮긴다.

승인된 목업(사람용): https://claude.ai/code/artifact/fde0e1ed-ad76-40ef-8a2d-0ff92169c191
