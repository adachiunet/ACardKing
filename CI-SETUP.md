# 方案 A:雲端編譯 + Windows 端簽名安裝(完全不用碰 Mac)

這份文件是給「一次都不想借 Mac」的路線用的。跟 `SETUP.md`(借一次實體 Mac、用 Xcode 圖形介面)是**兩條互相獨立、
效果相同**的路,選一條做完就好,不用兩條都做。

整體概念:GitHub 提供的雲端環境裡有真正的 macOS 機器可以編譯 App(這是免費的,你完全不會看到、也不用操作那台
機器),編譯出來的 App 刻意不簽名;真正的簽名這一步,改成在你自己的 Windows 電腦上用 **Sideloadly** 這個軟體,
用你的 Apple ID 完成,並直接透過傳輸線裝進 iPhone。全程你的電腦上不會出現任何 macOS 畫面。

## 這個資料夾裡新增了什麼

- `project.yml` — 描述這個 App 該怎麼組成 Xcode 專案的設定檔(給 **XcodeGen** 這個工具讀的,不是你要手動編輯的
  東西,除非你想改 Bundle Identifier)。
- `.github/workflows/build-ipa.yml` — GitHub Actions 的自動化腳本:你把這整個資料夾丟進 GitHub 之後,它會自動
  在雲端的 macOS 機器上跑起來,產生一個 `AcardKing.ipa` 檔案讓你下載。
- `CardKing/Assets.xcassets/` — App 圖示跟導覽列 Logo 已經先幫你組好成正式的圖示集格式(對應 `SETUP.md` 裡
  4b/4c 步驟原本要你手動在 Xcode 裡拖曳完成的動作,這條路線用設定檔直接生好,不需要你動手)。

## 步驟

1. **申請一個 GitHub 帳號**(免費):[github.com](https://github.com) 右上角 Sign up。

2. **新增一個 repository**:右上角「+」→ New repository。名字隨意(例如 `acardking`),**Public**(公開)就好
   ——這個專案沒有機密資訊,設成 Public 可以拿到完全免費、不限額度的雲端編譯時間;設成 Private 也可以,只是每個
   月的免費編譯時間有上限(對這個專案來說一次編譯用不了多少,通常不會超過)。

3. **把整個資料夾內容上傳上去**:不需要裝 git、不需要任何指令。進到剛剛新增的 repository 頁面 → 點
   **Add file → Upload files** → 把這個 zip 解壓縮後的**全部內容**(`CardKing/`、`project.yml`、`.github/`、
   `SETUP.md`、`CI-SETUP.md` 全部)拖進網頁裡 → 下面按 **Commit changes**。

   > 這一步唯一要注意的:資料夾結構要維持原樣,`.github/workflows/build-ipa.yml` 這個路徑不能跑掉,否則
   > GitHub 不會自動觸發編譯。網頁上傳通常會自動保留資料夾結構,拖曳整個解壓縮後的資料夾內容進去就好。

4. **等它自動編譯**:上傳完成後,點頁面上方的 **Actions** 分頁,應該會看到一個叫做「Build unsigned
   AcardKing.ipa」的流程自動開始跑(黃點在跑、綠勾是成功)。第一次跑通常 5–10 分鐘。

5. **下載編譯出來的 ipa**:流程跑完變成綠勾之後,點進去那次執行紀錄,最下面「Artifacts」會有一個
   `AcardKing-ipa`,點下去下載,解壓縮後就是 `AcardKing.ipa`。

6. **如果失敗了(紅叉)**:點進去看紅字的錯誤訊息,截圖給我,我來看是哪裡的設定要調整——這條路線比較新、
   沒有先在真正的 Mac 上驗證過每個環節,第一次沒有一次成功是有可能的,不是你操作錯。

7. **在 Windows 上裝 Sideloadly**:[sideloadly.io](https://sideloadly.io) 下載 Windows 版安裝。

8. **簽名並安裝到 iPhone**:iPhone 用傳輸線接上電腦 → 打開 Sideloadly → 把剛剛下載的 `AcardKing.ipa` 拖進去 →
   輸入你的 Apple ID 帳號密碼(這一步是 Sideloadly 自己跟 Apple 溝通,不會經過我這邊)→ 按 Start。等進度跑完,
   手機主畫面就會出現 AcardKing。

9. **第一次打開**:iPhone 上會顯示「未信任的開發者」——設定 App → 一般 → VPN 與裝置管理 → 選你的 Apple ID →
   信任。跟借 Mac 那條路線的最後一步完全一樣。

## 之後呢——7 天過期怎麼辦

免費 Apple ID 簽的 App 一樣是 7 天過期,這點兩條路線都一樣、沒有工具能繞過去。最簡單的做法就是每 7 天重複
第 8 步(Sideloadly 拖 ipa 進去、重新簽一次)。如果不想每 7 天手動做,可以改裝 **AltStore**
([altstore.io](https://altstore.io))取代 Sideloadly——AltStore 支援讓 Windows 電腦當「陪伴電腦」,
只要那台電腦定期開機、連上跟手機同一個 WiFi,它就會自動幫你重新簽署,不用你手動做這件事。想走這條的話跟我說,
我再補一份 AltStore 的設定步驟。
