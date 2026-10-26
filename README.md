# claude-statusline

Claude Code 입력 칸 아래에 한 줄을 띄웁니다.

```
🕐 마지막 활동 14:05 | 세션 42분 | Opus 5.5 | 컨텍스트 31% | 5h 18%(2시간13분) | 주간 40%(3일4시간) | 계정 myname
```

| 칸 | 뜻 |
|---|---|
| 마지막 활동 | 이 줄이 마지막으로 바뀐 시각 |
| 세션 | 이 대화를 연 지 몇 분 |
| 모델 | 지금 쓰는 모델 |
| 컨텍스트 | 대화 기억 칸을 얼마나 썼는지 |
| 5h · 주간 | 사용 한도를 얼마나 썼는지, 괄호 = 다시 채워지기까지 남은 시간 |
| 계정 | 이 창이 쓰는 계정 이메일의 @ 앞 (읽을 수 있을 때만) |
| $ | 이 대화에 든 돈 (0원이면 안 보임) |

## 설치 (한 줄)

윈도우는 **Git Bash**, 맥·리눅스는 **터미널**에 붙여 넣습니다.

```bash
curl -fsSL https://raw.githubusercontent.com/Raidcompany/claude-statusline/main/install.sh | bash
```

설정 폴더를 따로 쓰는 경우(예: `CLAUDE_CONFIG_DIR`)는 폴더를 뒤에 적습니다. 여러 개도 됩니다.

```bash
curl -fsSL https://raw.githubusercontent.com/Raidcompany/claude-statusline/main/install.sh | bash -s -- ~/.claude ~/work/.claude-config
```

설치 뒤 Claude Code 를 새로 열면 보입니다.

## 무엇이 바뀌나

- 설정 폴더에 `statusline.sh` 하나가 생깁니다.
- `settings.json` 에서 `statusLine` 칸만 바뀝니다. 다른 설정은 그대로입니다.
- 바꾸기 전 설정은 `settings.json.bak-statusline-<날짜-시각>` 으로 남습니다.
- 새로 깔아 주는 프로그램은 없습니다. 컴퓨터에 이미 있는 것(jq·node·python3·맥 osascript·윈도우 PowerShell 중 하나)으로 설정을 고칩니다.

## 되돌리기

남겨 둔 사본으로 덮으면 끝입니다.

```bash
cp ~/.claude/settings.json.bak-statusline-<날짜-시각> ~/.claude/settings.json
```

## 계정 칸과 비밀 값

- 계정 칸은 이 창의 로그인 토큰으로 Anthropic 에 "이 토큰 주인이 누구냐"를 한 번 물어 이메일 @ 앞만 보여 줍니다(1시간 기억).
- 토큰은 화면·파일·명령줄에 남기지 않습니다. 기억 파일 이름은 토큰을 거꾸로 알 수 없는 앞 12자 지문입니다.
- 맥은 토큰을 키체인에 두므로 계정 칸이 보통 안 보입니다(키체인은 읽지 않습니다).

## Orca 를 쓰는 경우

Orca 가 깔려 있으면 Orca 의 사용량 막대도 그대로 움직이도록 같은 정보를 Orca 에 넘겨 줍니다(15초에 한 번).

## 라이선스

MIT
