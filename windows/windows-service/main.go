package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"golang.org/x/sys/windows/svc"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	isService, err := svc.IsWindowsService()
	if err == nil && isService {
		paths, pathErr := parsePaths("run-service", args)
		if pathErr != nil {
			return fail(pathErr)
		}
		if err := svc.Run(serviceName, &serviceHandler{paths: paths}); err != nil {
			return fail(err)
		}
		return 0
	}
	if len(args) == 0 || args[0] == "help" || args[0] == "--help" || args[0] == "-h" {
		printHelp()
		return 0
	}
	command := args[0]
	paths, err := parsePaths(command, args[1:])
	if err != nil {
		return fail(err)
	}
	if isMutation(command) && !contains(args, "--elevated") && !isElevated() {
		if err := runElevated(args); err != nil {
			return fail(err)
		}
		return 0
	}
	switch command {
	case "install":
		err = installService(paths)
	case "uninstall":
		err = uninstallService()
	case "start":
		err = startService(paths)
	case "stop":
		err = stopService()
	case "restart":
		err = restartService(paths)
	case "status":
		status := queryStatus(paths)
		fmt.Printf("%s (installed=%t, mihomoPid=%d)\n", status.State, status.Installed, status.MihomoPID)
		if status.Message != "" {
			fmt.Println(status.Message)
		}
		return 0
	case "status-json":
		data, marshalErr := json.Marshal(queryStatus(paths))
		if marshalErr != nil {
			return fail(marshalErr)
		}
		fmt.Println(string(data))
		return 0
	case "autostart-json":
		data, marshalErr := json.Marshal(queryServiceAutoStart())
		if marshalErr != nil {
			return fail(marshalErr)
		}
		fmt.Println(string(data))
		return 0
	case "enable-autostart":
		err = setServiceAutoStart(true)
	case "disable-autostart":
		err = setServiceAutoStart(false)
	case "clear-runtime-message":
		err = clearRuntimeMessage(paths)
	case "restore-system-proxy":
		err = restoreSystemProxy(paths.ProxyBackup)
	case "core-update-json":
		appendUpdateLog(paths, "[mihomo] 开始检测内核更新")
		info, _, updateErr := checkCoreUpdate(paths)
		if updateErr != nil {
			appendUpdateLog(paths, "[mihomo] 检测更新失败：%v", updateErr)
			return fail(updateErr)
		}
		appendUpdateLog(
			paths,
			"[mihomo] 检测完成：当前=%s，官方=%s，可更新=%t",
			info.CurrentVersion,
			info.LatestVersion,
			info.UpdateAvailable,
		)
		data, marshalErr := json.Marshal(info)
		if marshalErr != nil {
			appendUpdateLog(paths, "[mihomo] 生成检测结果失败：%v", marshalErr)
			return fail(marshalErr)
		}
		fmt.Println(string(data))
		return 0
	case "singbox-update-json":
		appendUpdateLog(paths, "[sing-box] 开始检测内核更新")
		info, _, updateErr := checkSingBoxUpdate(paths)
		if updateErr != nil {
			appendUpdateLog(paths, "[sing-box] 检测更新失败：%v", updateErr)
			return fail(updateErr)
		}
		appendUpdateLog(
			paths,
			"[sing-box] 检测完成：当前=%s，官方=%s，可更新=%t",
			info.CurrentVersion,
			info.LatestVersion,
			info.UpdateAvailable,
		)
		data, marshalErr := json.Marshal(info)
		if marshalErr != nil {
			appendUpdateLog(paths, "[sing-box] 生成检测结果失败：%v", marshalErr)
			return fail(marshalErr)
		}
		fmt.Println(string(data))
		return 0
	case "update-core":
		appendUpdateLog(paths, "[mihomo] 开始更新内核")
		err = updateCore(paths)
		if err != nil {
			appendUpdateLog(paths, "[mihomo] 更新失败：%v", err)
		} else {
			appendUpdateLog(paths, "[mihomo] 更新完成")
		}
	case "update-singbox":
		appendUpdateLog(paths, "[sing-box] 开始更新内核")
		err = updateSingBox(paths)
		if err != nil {
			appendUpdateLog(paths, "[sing-box] 更新失败：%v", err)
		} else {
			appendUpdateLog(paths, "[sing-box] 更新完成")
		}
	case "run-service":
		err = svc.Run(serviceName, &serviceHandler{paths: paths})
	default:
		printHelp()
		return fail(fmt.Errorf("unknown command %q", command))
	}
	if err != nil {
		return fail(err)
	}
	return 0
}

func parsePaths(command string, args []string) (appPaths, error) {
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	base := flags.String("base", "", "program directory")
	dataDir := flags.String("data-dir", "", "shared data directory")
	proxyBackup := flags.String("proxy-backup", "", "system proxy backup file")
	elevated := flags.Bool("elevated", false, "internal elevation marker")
	_ = elevated
	if err := flags.Parse(args); err != nil {
		return appPaths{}, err
	}
	paths, err := resolvePaths(*base, *dataDir)
	if err != nil {
		return appPaths{}, err
	}
	paths.ProxyBackup = *proxyBackup
	return paths, nil
}

func isMutation(command string) bool {
	switch command {
	case "install", "uninstall", "start", "stop", "restart", "update-core", "update-singbox", "enable-autostart", "disable-autostart", "restore-system-proxy":
		return true
	default:
		return false
	}
}

func contains(args []string, wanted string) bool {
	for _, arg := range args {
		if arg == wanted {
			return true
		}
	}
	return false
}

func fail(err error) int {
	fmt.Fprintln(os.Stderr, "MclashService:", err)
	return 1
}

func printHelp() {
	fmt.Println(`MclashService manages the Mclash Windows service.

Usage:
  MclashService.exe <command> [--base <directory>] [--data-dir <directory>]

Commands:
  install uninstall start stop restart status status-json
  autostart-json enable-autostart disable-autostart
  clear-runtime-message restore-system-proxy
  core-update-json update-core singbox-update-json update-singbox
  run-service help`)
}
