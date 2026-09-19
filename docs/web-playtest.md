# 웹 테스트 운영

## 공유와 실행 범위

- 플레이 주소: **https://frotrue.github.io/nightwatch-array/**
- PC의 마우스·키보드 조작을 대상으로 한다. 설치·GitHub 로그인은 필요하지 않다.
- GitHub Pro 계정의 `frotrue/nightwatch-array` 저장소는 비공개이며 게임 페이지는 공개다.
  개발 문서나 저장소 전체를 사이트에 올리는 방식이 아니라 `build/web`만 배포한다.
- 별도의 서버 API나 스레드용 격리 헤더 없이 실행하는 WebGL 2.0 단일 스레드 빌드다.
  Windows의 Vulkan 설정과 게임의 연구·보상·엔딩은 유지한다.
- 현재 배포에는 전체 게임이 포함되며 별도의 시간 제한 데모는 아니다.
  터치 조작과 모바일 플레이는 지원 범위가 아니다.

로컬 내보내기·ZIP 생성 명령은 [README](../README.md#pc-브라우저-테스트판)에 있다.
`127.0.0.1` 주소는 서버를 켠 PC에서만 사용할 수 있다. 외부 테스터에게는 위 공개 주소를 보낸다.

## 저장과 브라우저 차이

저장은 접속 출처와 브라우저 프로필의 로컬 저장소에 남는다. Windows 저장 파일과
동기화되지 않으며 로컬 테스트 주소와 공개 Pages 주소의 저장도 별개다.
사이트 데이터 삭제, 시크릿 모드 종료, 저장 차단 설정은 저장 유지에 영향을 줄 수 있다.
다른 브라우저나 기기로 옮겼을 때 이전 진행이 자동으로 나타나는 서비스는 아니다.

브라우저의 오디오 정책에 따라 최초 클릭·키 입력 후 소리가 활성화된다.
Windows 전용 CPU/GPU 측정 도우미는 실행하지 않는다. 단일 스레드에서도 같은 수치 계산을
사용하지만 Windows판과 동일한 성능을 보장하지는 않는다.
한글은 동봉된 IBM Plex Sans KR을 사용하며 계기용 고정폭 글꼴과 기본 팝업의 대체 글꼴도 지정한다.

## 배포와 검증

워크플로: [Publish web playtest](../.github/workflows/web-playtest-pages.yml).
수동 실행만 허용하고 `main`에서만 빌드한다. 일반 푸시나 PR 병합은 배포를 시작하지 않는다.

1. 변경 범위에 맞는 검사와 필수 Windows 내보내기를 완료한다.
2. 변경을 커밋하고 PR을 `main`에 병합·푸시한다.
3. 원격 `main`의 배포 대상 커밋을 기록하고 워크플로를 실행한다.

```powershell
$deployCommit = gh api repos/frotrue/nightwatch-array/commits/main --jq .sha
gh workflow run web-playtest-pages.yml --ref main
gh run list --workflow web-playtest-pages.yml --limit 5 --json databaseId,headSha,status,conclusion,url
```

출력에서 `headSha`가 `$deployCommit`과 같은 새 실행의 ID를 확인한다.
목록의 예전 성공이나 `queued` 상태를 새 배포 성공으로 해석하지 않는다.
동시에 다른 병합이 있었다면 실제 실행의 `headSha`를 확인해 배포할 소스가 맞는지 판단한다.

```powershell
# <실행ID>를 위에서 확인한 숫자로 바꾼다.
gh run watch <실행ID> --exit-status
```

워크플로는 SHA-256으로 고정 버전 Godot 4.7.2와 템플릿을 확인하고 임포트·웹 내보내기를 수행한다.
엔진/스크립트 오류와 필수 출력 누락을 검사한 후 `build/web`을 Pages 아티팩트로 전달한다.
검사 전체를 GitHub에서 다시 실행하는 워크플로는 아니므로 배포 전 로컬 검증을 생략하지 않는다.
빌드 로그는 `web-export-logs` 아티팩트로 7일간 보존한다.

성공 후 공개된 리비전도 대조한다.

```powershell
$publishedCommit = (Invoke-WebRequest 'https://frotrue.github.io/nightwatch-array/build-revision.txt').Content.Trim()
if ($publishedCommit -ne $deployCommit) { throw "Published revision does not match the requested build" }
```

새 브라우저 세션에서 로딩, 한글, 첫 입력, 연구 구매, 새로고침 후 저장 복원과 콘솔 오류를 확인한다.
`build-revision.txt`에는 **실제로 배포한 커밋**이 남는다. 문서만 병합하고 재배포하지 않았다면
최신 `main`과 달라도 정상이며, 이를 이유로 게임을 다시 배포할 필요는 없다.

실패하면 해당 실행의 로그와 실패 단계를 확인하고 원인을 수정한 뒤 다시 실행한다.
배포 실패나 리비전 불일치가 남은 상태를 완료로 보고하지 않는다.

## 초견 테스트 기록

초기 확인에는 이 장르를 즐겨 본 외부 플레이어 3~5명의 반응을 더 모으는 방식을 제안한다.
이 인원은 작은 반복 문제를 찾기 위한 제안이며 출시 합격선이나 시장 대표 표본이 아니다.
테스트를 실제로 진행했는지와 모집·실행 계획을 구분한다.

- 날짜, 배포 리비전, 브라우저·기기, 새 저장인지 이어 하기인지 기록한다.
- 평소 즐기는 장르와 비슷한 인크리멘탈 경험을 확인한다. 이름 등 개인정보는 필요하지 않다.
- 개발자가 해설하거나 끝까지 하도록 요구하지 않고, 도움을 줬다면 시점과 내용을 기록한다.
- 중단·재개 시점, 중단 이유의 실제 표현, 구매한 연구와 체감한 변화, 스스로 계속했는지를 기록한다.
- 관찰 사실, 플레이어 발언, 개발자의 원인 가설을 분리한다.
  특정 연구 미구매나 이해 부족을 확인하지 않았다면 이유를 추정해 채워 넣지 않는다.

기록은 익명 사례별로 정리하고 배포 버전이 다른 테스트를 같은 조건으로 합치지 않는다.
브라우저판은 이 항목을 자동 수집·전송하지 않는다. 사람이 남기는 메모와 피드백이 필요하다.
[외부 선택 모드 기록 규약](playtest-recording.md)은 경제 시뮬레이터용이며,
그 합성 관측과 LLM 구매 선택은 사람의 조작감·재미·완주율을 입증하지 않는다.

첫 배포의 확인 범위와 기존 초견 반응은 [첫 배포 기록](history/web-playtest-launch-2026-09-18.md)에 보존한다.
