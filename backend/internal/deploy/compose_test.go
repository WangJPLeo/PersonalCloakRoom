package deploy

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestComposePreservesModelEnvironmentFiles(t *testing.T) {
	docker, err := exec.LookPath("docker")
	if err != nil {
		t.Skip("Docker CLI is needed to validate Compose configuration")
	}
	if err := exec.Command(docker, "compose", "version").Run(); err != nil {
		t.Skip("Docker Compose is unavailable")
	}
	for _, tc := range []struct {
		name, source, composeDir, rootEnv, wantKey string
	}{
		{"root reads backend env", "../../../docker-compose.yml", "", "", "backend-test-key"},
		{"root env takes precedence", "../../../docker-compose.yml", "", "ARK_API_KEY=root-test-key\n", "root-test-key"},
		{"backend reads its env", "../../docker-compose.yml", "backend", "", "backend-test-key"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			if err := os.Mkdir(filepath.Join(root, "backend"), 0755); err != nil {
				t.Fatal(err)
			}
			content, err := os.ReadFile(tc.source)
			if err != nil {
				t.Fatal(err)
			}
			composePath := filepath.Join(root, tc.composeDir, "docker-compose.yml")
			files := map[string][]byte{
				composePath:                            content,
				filepath.Join(root, "backend", ".env"): []byte("ARK_API_KEY=backend-test-key\nARK_MODEL=deployment-test-model\n"),
			}
			if tc.rootEnv != "" {
				files[filepath.Join(root, ".env")] = []byte(tc.rootEnv)
			}
			for path, data := range files {
				if err := os.WriteFile(path, data, 0600); err != nil {
					t.Fatal(err)
				}
			}
			cmd := exec.Command(docker, "compose", "--env-file", os.DevNull, "-f", composePath, "config", "--format", "json")
			cmd.Dir = filepath.Dir(composePath)
			for _, entry := range os.Environ() {
				if !strings.HasPrefix(entry, "ARK_API_KEY=") && !strings.HasPrefix(entry, "ARK_MODEL=") && !strings.HasPrefix(entry, "COMPOSE_") {
					cmd.Env = append(cmd.Env, entry)
				}
			}
			output, err := cmd.Output()
			if err != nil {
				t.Fatal("Compose configuration could not be rendered")
			}
			var config struct {
				Services map[string]struct {
					Environment map[string]string `json:"environment"`
				} `json:"services"`
			}
			if err := json.Unmarshal(output, &config); err != nil {
				t.Fatal(err)
			}
			env := config.Services["personalcloakroom"].Environment
			if env["ARK_API_KEY"] != tc.wantKey || env["ARK_MODEL"] != "deployment-test-model" {
				t.Fatal("Compose must preserve model variables from env_file instead of replacing them with empty interpolation")
			}
		})
	}
}
