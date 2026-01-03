// Package workspace provides functionality for discovering, initializing, and
// managing Morphir workspaces.
//
// # Overview
//
// A Morphir workspace is a directory containing a morphir.toml configuration
// file. This package provides functions to:
//   - Discover existing workspaces by walking up the directory tree
//   - Initialize new workspaces with standard directory structure
//   - Access important paths within a workspace
//
// # Workspace Structure
//
// A typical Morphir workspace has the following structure:
//
//	my-project/
//	├── morphir.toml              # Project configuration
//	├── .morphir/                 # Morphir working directory
//	│   ├── morphir.user.toml     # User-specific overrides (gitignored)
//	│   ├── out/                  # Generated output
//	│   ├── cache/                # Build cache
//	│   └── .gitignore            # Standard ignores
//	└── src/                      # Source files
//
// Alternatively, the configuration can be placed inside .morphir/:
//
//	my-project/
//	├── .morphir/
//	│   ├── morphir.toml          # Project configuration (hidden style)
//	│   ├── morphir.user.toml     # User-specific overrides
//	│   ├── out/                  # Generated output
//	│   └── cache/                # Build cache
//	└── src/                      # Source files
//
// # Discovering Workspaces
//
// Use Discover to find a workspace starting from the current directory:
//
//	ws, err := workspace.Discover()
//	if err != nil {
//	    if errors.Is(err, workspace.ErrNotFound) {
//	        fmt.Println("No workspace found")
//	    } else {
//	        log.Fatal(err)
//	    }
//	}
//	fmt.Println("Workspace root:", ws.Root())
//
// Use DiscoverFrom to start from a specific directory:
//
//	ws, err := workspace.DiscoverFrom("/path/to/start")
//	if err != nil {
//	    log.Fatal(err)
//	}
//	fmt.Println("Config file:", ws.ConfigPath())
//
// # Initializing Workspaces
//
// Use Init to create a new workspace:
//
//	result, err := workspace.Init(workspace.InitOptions{
//	    Path:  "/path/to/new-project",
//	    Name:  "my-project",
//	    Style: workspace.ConfigStyleRoot,
//	})
//	if err != nil {
//	    log.Fatal(err)
//	}
//	fmt.Println("Created workspace at:", result.Workspace().Root())
//	fmt.Println("Created files:", result.CreatedFiles())
//
// The Style option controls where morphir.toml is placed:
//   - ConfigStyleRoot: Place morphir.toml in the workspace root (default)
//   - ConfigStyleHidden: Place morphir.toml inside .morphir/ directory
//
// # Workspace Paths
//
// The Workspace type provides convenient accessors for standard paths:
//
//	ws, _ := workspace.Discover()
//
//	ws.Root()           // "/path/to/project"
//	ws.ConfigPath()     // "/path/to/project/morphir.toml"
//	ws.MorphirDir()     // "/path/to/project/.morphir"
//	ws.OutDir()         // "/path/to/project/.morphir/out"
//	ws.CacheDir()       // "/path/to/project/.morphir/cache"
//	ws.UserConfigPath() // "/path/to/project/.morphir/morphir.user.toml"
//
// # Error Handling
//
// The package provides typed errors for specific conditions:
//
//	ws, err := workspace.Discover()
//	if err != nil {
//	    switch {
//	    case errors.Is(err, workspace.ErrNotFound):
//	        // No workspace found in directory tree
//	    case errors.Is(err, workspace.ErrPathNotExist):
//	        // Starting path does not exist
//	    default:
//	        // Other error (e.g., permission denied)
//	    }
//	}
//
//	result, err := workspace.Init(opts)
//	if err != nil {
//	    var alreadyExists *workspace.AlreadyExistsError
//	    if errors.As(err, &alreadyExists) {
//	        fmt.Printf("Workspace already exists at: %s\n", alreadyExists.ExistingRoot)
//	    }
//	}
//
// # Thread Safety
//
// All types in this package are immutable and safe for concurrent use.
// The Workspace type uses value receivers and returns defensive copies
// where appropriate.
package workspace
