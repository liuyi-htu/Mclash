package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const mihomoReleaseAPI = "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
const singBoxReleaseAPI = "https://api.github.com/repos/SagerNet/sing-box/releases/latest"

type coreUpdateInfo struct {
	CurrentVersion  string `json:"currentVersion"`
	LatestVersion   string `json:"latestVersion"`
	UpdateAvailable bool   `json:"updateAvailable"`
}

type githubRelease struct {
	TagName string `json:"tag_name"`
	Assets  []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
		Digest             string `json:"digest"`
	} `json:"assets"`
}

var versionPattern = regexp.MustCompile(`(?i)\bv?(\d+)\.(\d+)\.(\d+)\b`)

var updateHTTPClient = func() *http.Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	dialer := &net.Dialer{Timeout: 30 * time.Second, KeepAlive: 30 * time.Second}
	transport.DialContext = func(ctx context.Context, _, address string) (net.Conn, error) {
		return dialer.DialContext(ctx, "tcp4", address)
	}
	transport.TLSHandshakeTimeout = 60 * time.Second
	transport.ResponseHeaderTimeout = 60 * time.Second
	return &http.Client{Transport: transport}
}()

func appendUpdateLog(paths appPaths, format string, args ...any) {
	if !debugLoggingEnabled(paths) {
		return
	}
	if err := paths.ensureDataDirs(); err != nil {
		return
	}
	file, err := os.OpenFile(
		filepath.Join(paths.Logs, "update.log"),
		os.O_CREATE|os.O_APPEND|os.O_WRONLY,
		0o644,
	)
	if err != nil {
		return
	}
	defer file.Close()
	message := fmt.Sprintf(format, args...)
	_, _ = fmt.Fprintf(
		file,
		"%s %s\n",
		time.Now().Format("2006-01-02 15:04:05"),
		message,
	)
}

func checkCoreUpdate(paths appPaths) (coreUpdateInfo, githubRelease, error) {
	current, err := readMihomoVersion(paths.MihomoExe)
	if err != nil {
		return coreUpdateInfo{}, githubRelease{}, err
	}
	release, err := fetchLatestMihomoRelease()
	if err != nil {
		return coreUpdateInfo{}, githubRelease{}, err
	}
	latest, err := normalizeVersion(release.TagName)
	if err != nil {
		return coreUpdateInfo{}, githubRelease{}, fmt.Errorf("invalid official release version: %w", err)
	}
	comparison, err := compareVersions(current, latest)
	if err != nil {
		return coreUpdateInfo{}, githubRelease{}, err
	}
	return coreUpdateInfo{
		CurrentVersion:  current,
		LatestVersion:   latest,
		UpdateAvailable: comparison < 0,
	}, release, nil
}

func updateCore(paths appPaths) error {
	info, release, err := checkCoreUpdate(paths)
	if err != nil {
		return err
	}
	if !info.UpdateAvailable {
		appendUpdateLog(
			paths,
			"[mihomo] 当前内核已是官方最新版，无需更新：当前=%s，官方=%s",
			info.CurrentVersion,
			info.LatestVersion,
		)
		return nil
	}
	wantedName := "mihomo-windows-amd64-compatible-v" + info.LatestVersion + ".zip"
	var downloadURL, digest string
	for _, asset := range release.Assets {
		if strings.EqualFold(asset.Name, wantedName) {
			downloadURL = asset.BrowserDownloadURL
			digest = asset.Digest
			break
		}
	}
	if downloadURL == "" {
		return fmt.Errorf("official release does not contain %s", wantedName)
	}
	if !strings.HasPrefix(strings.ToLower(digest), "sha256:") {
		return fmt.Errorf("official release asset has no SHA-256 digest")
	}
	archive, err := downloadCoreArchive(downloadURL)
	if err != nil {
		return err
	}
	expected, err := hex.DecodeString(strings.TrimPrefix(strings.ToLower(digest), "sha256:"))
	if err != nil {
		return fmt.Errorf("decode official SHA-256 digest: %w", err)
	}
	actual := sha256.Sum256(archive)
	if !bytes.Equal(actual[:], expected) {
		return fmt.Errorf("downloaded mihomo SHA-256 does not match the official digest")
	}
	binary, err := extractMihomoExecutable(archive)
	if err != nil {
		return err
	}
	temporary := paths.MihomoExe + ".update"
	_ = os.Remove(temporary)
	if err := os.WriteFile(temporary, binary, 0o755); err != nil {
		return fmt.Errorf("write updated mihomo: %w", err)
	}
	defer os.Remove(temporary)
	return activateCoreUpdate(paths, "mihomo", paths.MihomoExe, temporary, info.LatestVersion, readMihomoVersion)
}

func checkSingBoxUpdate(paths appPaths) (coreUpdateInfo, githubRelease, error) {
	current, err := readCoreVersion(paths.SingBoxExe, "version")
	if err != nil {
		return coreUpdateInfo{}, githubRelease{}, err
	}
	release, err := fetchGitHubRelease(singBoxReleaseAPI, "sing-box")
	if err != nil {
		return coreUpdateInfo{}, githubRelease{}, err
	}
	latest, err := normalizeVersion(release.TagName)
	if err != nil {
		return coreUpdateInfo{}, githubRelease{}, err
	}
	comparison, err := compareVersions(current, latest)
	if err != nil {
		return coreUpdateInfo{}, githubRelease{}, err
	}
	return coreUpdateInfo{CurrentVersion: current, LatestVersion: latest, UpdateAvailable: comparison < 0}, release, nil
}

func updateSingBox(paths appPaths) error {
	info, release, err := checkSingBoxUpdate(paths)
	if err != nil {
		return err
	}
	if !info.UpdateAvailable {
		appendUpdateLog(
			paths,
			"[sing-box] 当前内核已是官方最新版，无需更新：当前=%s，官方=%s",
			info.CurrentVersion,
			info.LatestVersion,
		)
		return nil
	}
	wantedName := "sing-box-" + info.LatestVersion + "-windows-amd64.zip"
	var downloadURL, digest string
	for _, asset := range release.Assets {
		if strings.EqualFold(asset.Name, wantedName) {
			downloadURL, digest = asset.BrowserDownloadURL, asset.Digest
			break
		}
	}
	if downloadURL == "" {
		return fmt.Errorf("official release does not contain %s", wantedName)
	}
	archive, err := downloadCoreArchive(downloadURL)
	if err != nil {
		return err
	}
	if !strings.HasPrefix(strings.ToLower(digest), "sha256:") {
		return fmt.Errorf("official release asset has no SHA-256 digest")
	}
	expected, err := hex.DecodeString(strings.TrimPrefix(strings.ToLower(digest), "sha256:"))
	if err != nil {
		return err
	}
	actual := sha256.Sum256(archive)
	if !bytes.Equal(actual[:], expected) {
		return fmt.Errorf("downloaded sing-box SHA-256 mismatch")
	}
	binary, err := extractMihomoExecutable(archive)
	if err != nil {
		return err
	}
	temporary := paths.SingBoxExe + ".update"
	_ = os.Remove(temporary)
	if err := os.WriteFile(temporary, binary, 0o755); err != nil {
		return err
	}
	defer os.Remove(temporary)
	return activateCoreUpdate(
		paths,
		"sing-box",
		paths.SingBoxExe,
		temporary,
		info.LatestVersion,
		func(path string) (string, error) { return readCoreVersion(path, "version") },
	)
}

var (
	queryServiceStatus = queryStatus
	stopProxyService   = stopService
	startProxyService  = startService
)

// activateCoreUpdate is called only after the update has been fully downloaded,
// verified, extracted, and written to temporary. This keeps the proxy online
// during the slow network operation and limits downtime to the file swap.
func activateCoreUpdate(
	paths appPaths,
	name, target, temporary, latestVersion string,
	readVersion func(string) (string, error),
) error {
	status := queryServiceStatus(paths)
	if status.State == "start_pending" || status.State == "stop_pending" {
		return fmt.Errorf("cannot update %s while the Mclash service is changing state", name)
	}
	wasRunning := status.State == "running"
	if wasRunning {
		appendUpdateLog(paths, "[%s] 下载及校验完成，正在停止代理", name)
		if err := stopProxyService(); err != nil {
			return fmt.Errorf("stop proxy before replacing %s: %w", name, err)
		}
	}

	backup := target + ".backup"
	_ = os.Remove(backup)
	if err := os.Rename(target, backup); err != nil {
		return restartAfterUpdateFailure(paths, name, wasRunning, fmt.Errorf("back up current %s: %w", name, err))
	}
	if err := os.Rename(temporary, target); err != nil {
		_ = os.Rename(backup, target)
		return restartAfterUpdateFailure(paths, name, wasRunning, fmt.Errorf("activate updated %s: %w", name, err))
	}

	installed, verifyErr := readVersion(target)
	if verifyErr != nil || installed != latestVersion {
		_ = os.Remove(target)
		_ = os.Rename(backup, target)
		return restartAfterUpdateFailure(
			paths,
			name,
			wasRunning,
			fmt.Errorf("updated %s failed version verification: got %q: %v", name, installed, verifyErr),
		)
	}

	if wasRunning {
		appendUpdateLog(paths, "[%s] 内核替换完成，正在重启代理", name)
		if err := startProxyService(paths); err != nil {
			_ = os.Remove(target)
			_ = os.Rename(backup, target)
			restartErr := startProxyService(paths)
			if restartErr != nil {
				return fmt.Errorf("start proxy with updated %s: %w; rolled back but failed to restart old core: %v", name, err, restartErr)
			}
			return fmt.Errorf("start proxy with updated %s: %w; rolled back to the previous core", name, err)
		}
	}
	_ = os.Remove(backup)
	return nil
}

func restartAfterUpdateFailure(paths appPaths, name string, wasRunning bool, updateErr error) error {
	if !wasRunning {
		return updateErr
	}
	if err := startProxyService(paths); err != nil {
		return fmt.Errorf("%w; also failed to restart proxy with the previous %s core: %v", updateErr, name, err)
	}
	return updateErr
}

func readCoreVersion(path string, argument string) (string, error) {
	if err := validateRegularNonEmpty(path, ".exe"); err != nil {
		return "", err
	}
	cmd := exec.Command(path, argument)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", err
	}
	return normalizeVersion(string(output))
}

func fetchGitHubRelease(api, name string) (githubRelease, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, api, nil)
	if err != nil {
		return githubRelease{}, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "Mclash-Windows")
	response, err := updateHTTPClient.Do(req)
	if err != nil {
		return githubRelease{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return githubRelease{}, fmt.Errorf("query %s release: HTTP %d", name, response.StatusCode)
	}
	var release githubRelease
	err = json.NewDecoder(io.LimitReader(response.Body, 4<<20)).Decode(&release)
	return release, err
}

func fetchLatestMihomoRelease() (githubRelease, error) {
	var lastErr error
	for attempt := 1; attempt <= 3; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, mihomoReleaseAPI, nil)
		if err != nil {
			cancel()
			return githubRelease{}, err
		}
		req.Header.Set("Accept", "application/vnd.github+json")
		req.Header.Set("User-Agent", "Mclash-Windows")
		response, err := updateHTTPClient.Do(req)
		if err == nil && response.StatusCode == http.StatusOK {
			var release githubRelease
			decodeErr := json.NewDecoder(io.LimitReader(response.Body, 4<<20)).Decode(&release)
			response.Body.Close()
			cancel()
			if decodeErr != nil {
				return githubRelease{}, fmt.Errorf("decode official mihomo release: %w", decodeErr)
			}
			return release, nil
		}
		if response != nil {
			lastErr = fmt.Errorf("HTTP %d", response.StatusCode)
			response.Body.Close()
		} else {
			lastErr = err
		}
		cancel()
		if attempt < 3 {
			time.Sleep(time.Duration(attempt) * time.Second)
		}
	}
	return githubRelease{}, fmt.Errorf("query official mihomo release: %w", lastErr)
}

func downloadCoreArchive(url string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Mclash-Windows")
	response, err := updateHTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("download mihomo update: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("download mihomo update: HTTP %d", response.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, 200<<20))
	if err != nil {
		return nil, fmt.Errorf("read mihomo update: %w", err)
	}
	return data, nil
}

func extractMihomoExecutable(archive []byte) ([]byte, error) {
	reader, err := zip.NewReader(bytes.NewReader(archive), int64(len(archive)))
	if err != nil {
		return nil, fmt.Errorf("open mihomo update archive: %w", err)
	}
	for _, file := range reader.File {
		if !strings.HasSuffix(strings.ToLower(filepath.Base(file.Name)), ".exe") {
			continue
		}
		stream, err := file.Open()
		if err != nil {
			return nil, err
		}
		data, readErr := io.ReadAll(io.LimitReader(stream, 150<<20))
		stream.Close()
		if readErr != nil {
			return nil, readErr
		}
		if len(data) == 0 {
			return nil, fmt.Errorf("mihomo executable in update archive is empty")
		}
		return data, nil
	}
	return nil, fmt.Errorf("mihomo update archive contains no executable")
}

func readMihomoVersion(path string) (string, error) {
	if err := validateRegularNonEmpty(path, ".exe"); err != nil {
		return "", err
	}
	cmd := exec.Command(path, "-v")
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("read mihomo version: %w", err)
	}
	return normalizeVersion(string(output))
}

func normalizeVersion(value string) (string, error) {
	match := versionPattern.FindStringSubmatch(value)
	if match == nil {
		return "", fmt.Errorf("version not found in %q", strings.TrimSpace(value))
	}
	return strings.Join(match[1:4], "."), nil
}

func compareVersions(left, right string) (int, error) {
	parse := func(value string) ([3]int, error) {
		var result [3]int
		parts := strings.Split(value, ".")
		if len(parts) != 3 {
			return result, fmt.Errorf("invalid semantic version %q", value)
		}
		for i, part := range parts {
			number, err := strconv.Atoi(part)
			if err != nil {
				return result, fmt.Errorf("invalid semantic version %q", value)
			}
			result[i] = number
		}
		return result, nil
	}
	l, err := parse(left)
	if err != nil {
		return 0, err
	}
	r, err := parse(right)
	if err != nil {
		return 0, err
	}
	for i := range l {
		if l[i] < r[i] {
			return -1, nil
		}
		if l[i] > r[i] {
			return 1, nil
		}
	}
	return 0, nil
}
