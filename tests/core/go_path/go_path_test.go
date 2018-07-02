/* Copyright 2018 The Bazel Authors. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package go_path

import (
	"archive/zip"
	"flag"
	"io"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var copyPath, linkPath, archivePath, nodataPath string

var files = []string{
	"extra.txt",
	"src/",
	"-src/example.com/repo/cmd/bin/bin",
	"-src/testmain/testmain.go",
	"src/example.com/repo/cmd/bin/bin.go",
	"src/example.com/repo/pkg/lib/lib.go",
	"src/example.com/repo/pkg/lib/embed_test.go",
	"src/example.com/repo/pkg/lib/internal_test.go",
	"src/example.com/repo/pkg/lib/external_test.go",
	"-src/example.com/repo/pkg/lib_test/embed_test.go",
	"src/example.com/repo/pkg/lib/data.txt",
	"src/example.com/repo/pkg/lib/testdata/testdata.txt",
	"src/example.com/repo/vendor/example.com/repo2/vendored.go",
}

func TestMain(m *testing.M) {
	flag.StringVar(&copyPath, "copy_path", "", "path to copied go_path")
	flag.StringVar(&linkPath, "link_path", "", "path to symlinked go_path")
	flag.StringVar(&archivePath, "archive_path", "", "path to archive go_path")
	flag.StringVar(&nodataPath, "nodata_path", "", "path to go_path without data")
	flag.Parse()
	os.Exit(m.Run())
}

func TestCopyPath(t *testing.T) {
	if copyPath == "" {
		t.Fatal("-copy_path not set")
	}
	checkPath(t, copyPath, files, os.FileMode(0))
}

func TestLinkPath(t *testing.T) {
	if linkPath == "" {
		t.Fatal("-link_path not set")
	}
	checkPath(t, linkPath, files, os.ModeSymlink)
}

func TestArchivePath(t *testing.T) {
	if archivePath == "" {
		t.Fatal("-archive_path not set")
	}
	dir, err := ioutil.TempDir(os.Getenv("TEST_TEMPDIR"), "TestArchivePath")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(dir)

	z, err := zip.OpenReader(archivePath)
	if err != nil {
		t.Fatalf("error opening zip: %v", err)
	}
	defer z.Close()
	for _, f := range z.File {
		r, err := f.Open()
		if err != nil {
			t.Fatalf("error reading file %s: %v", f.Name, err)
		}
		dstPath := filepath.Join(dir, filepath.FromSlash(f.Name))
		if err := os.MkdirAll(filepath.Dir(dstPath), 0777); err != nil {
			t.Fatalf("error creating directory %s: %v", filepath.Dir(dstPath), err)
		}
		w, err := os.Create(dstPath)
		if err != nil {
			t.Fatalf("error creating file %s: %v", dstPath, err)
		}
		if _, err := io.Copy(w, r); err != nil {
			w.Close()
			t.Fatalf("error writing file %s: %v", dstPath, err)
		}
		if err := w.Close(); err != nil {
			t.Fatalf("error closing file %s: %v", dstPath, err)
		}
	}

	checkPath(t, dir, files, os.FileMode(0))
}

func TestNoDataPath(t *testing.T) {
	if nodataPath == "" {
		t.Fatal("-nodata_path not set")
	}
	files := []string{
		"extra.txt",
		"src/example.com/repo/pkg/lib/lib.go",
		"-src/example.com/repo/pkg/lib/data.txt",
	}
	checkPath(t, nodataPath, files, os.FileMode(0))
}

// checkPath checks that dir contains a list of files. files is a list of
// slash-separated paths relative to dir. Files that start with "-" should be
// absent. Files that end with "/" should be directories. Other files should
// be of fileType.
func checkPath(t *testing.T, dir string, files []string, fileType os.FileMode) {
	for _, f := range files {
		wantType := fileType
		wantAbsent := false
		if strings.HasPrefix(f, "-") {
			f = f[1:]
			wantAbsent = true
		}
		if strings.HasSuffix(f, "/") {
			wantType = os.ModeDir
		}
		path := filepath.Join(dir, filepath.FromSlash(f))
		st, err := os.Lstat(path)
		if wantAbsent {
			if err == nil {
				t.Errorf("found %s: should not be present", path)
			} else if !os.IsNotExist(err) {
				t.Error(err)
			}
		} else {
			if err != nil {
				if os.IsNotExist(err) {
					t.Errorf("%s is missing", path)
				} else {
					t.Error(err)
				}
				continue
			}
			gotType := st.Mode() & os.ModeType
			if gotType != wantType {
				t.Errorf("%s: got type %s; want type %s .. %s", path, gotType, wantType, st.Mode())
			}
		}
	}
}
