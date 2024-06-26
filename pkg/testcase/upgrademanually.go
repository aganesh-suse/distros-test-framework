package testcase

import (
	"fmt"
	"strings"
	"sync"

	"github.com/rancher/distros-test-framework/factory"
	"github.com/rancher/distros-test-framework/pkg/customflag"
	"github.com/rancher/distros-test-framework/shared"

	. "github.com/onsi/ginkgo/v2"
)

// TestUpgradeClusterManually upgrades the cluster "manually"
func TestUpgradeClusterManually(version string) error {
	if version == "" {
		return shared.ReturnLogError("please provide a non-empty version or commit to upgrade to")
	}
	shared.PrintClusterState()
	shared.LogLevel("info", fmt.Sprintf("Upgrading cluster to: %s\n", version))

	cluster := factory.ClusterConfig(GinkgoT())

	if cluster.NumServers == 0 && cluster.NumAgents == 0 {
		return shared.ReturnLogError("no nodes found to upgrade")
	}

	if cluster.NumServers > 0 {
		if err := upgradeServer(version, cluster.ServerIPs); err != nil {
			return err
		}
	}

	if cluster.NumAgents > 0 {
		if err := upgradeAgent(version, cluster.AgentIPs); err != nil {
			return err
		}
	}

	return nil
}

// upgradeProduct upgrades a node server or agent type to the specified version
func upgradeProduct(nodeType string, installType string, ips []string) error {
	var wg sync.WaitGroup
	errCh := make(chan error, len(ips))

	upgradeCommand := getInstallCmd(installType, nodeType)

	for _, ip := range ips {
		wg.Add(1)
		go func(ip, upgradeCommand string) {
			defer wg.Done()
			defer GinkgoRecover()

			shared.LogLevel("info", fmt.Sprintf("Upgrading %s %s: %s", ip, nodeType, upgradeCommand))

			if _, err := shared.RunCommandOnNode(upgradeCommand, ip); err != nil {
				shared.LogLevel("\nwarn", fmt.Sprintf("upgrading %s %s: %v", nodeType, ip, err))
				errCh <- err
				return
			}

			product, err := shared.Product()
			if err != nil {
				return
			}

			shared.LogLevel("info", fmt.Sprintf("Restarting %s %s", nodeType, ip))
			shared.RestartCluster(product, ip)
		}(ip, upgradeCommand)
	}
	wg.Wait()
	close(errCh)

	return nil
}

func getInstallCmd(installType string, nodeType string) string {
	var installFlag string
	var installCmd string
	product, err := shared.Product()
	if err != nil {
		return err.Error()
	}

	var channel = getChannel()

	if strings.HasPrefix(installType, "v") {
		installFlag = fmt.Sprintf("INSTALL_%s_VERSION=%s", strings.ToUpper(product), installType)
	} else {
		installFlag = fmt.Sprintf("INSTALL_%s_COMMIT=%s", strings.ToUpper(product), installType)
	}

	installCmd = fmt.Sprintf("curl -sfL https://get.%s.io | sudo %%s %%s sh -s - %s", product, nodeType)

	return fmt.Sprintf(installCmd, installFlag, channel)
}

func getChannel() string {
	product, err := shared.Product()
	if err != nil {
		return err.Error()
	}

	var defaultChannel = fmt.Sprintf("INSTALL_%s_CHANNEL=%s", strings.ToUpper(product), "stable")

	if customflag.ServiceFlag.Channel.String() != "" {
		return fmt.Sprintf("INSTALL_%s_CHANNEL=%s", strings.ToUpper(product),
			customflag.ServiceFlag.Channel.String())
	}

	return defaultChannel
}

func upgradeServer(installType string, serverIPs []string) error {
	return upgradeProduct("server", installType, serverIPs)
}

func upgradeAgent(installType string, agentIPs []string) error {
	return upgradeProduct("agent", installType, agentIPs)
}
