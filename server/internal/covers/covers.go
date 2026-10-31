// Package covers stores album art: source images are hashed (for
// de-duplication) and resized once into fixed JPEG sizes on disk.
package covers

import (
	"bytes"
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png"
	"os"
	"path/filepath"
	"slices"

	"golang.org/x/image/draw"
	_ "golang.org/x/image/webp"
)

// Sizes are the generated square-ish bounding boxes, in pixels.
var Sizes = []int{64, 300, 800}

type Cache struct {
	dir string
}

func New(dir string) (*Cache, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	return &Cache{dir: dir}, nil
}

// Hash returns the content hash used as cover identity.
func Hash(img []byte) string {
	h := sha1.Sum(img)
	return hex.EncodeToString(h[:])
}

// Path returns the file for a cover at a given size (snapped to the nearest
// generated size that is >= the request).
func (c *Cache) Path(hash string, size int) string {
	return filepath.Join(c.dir, hash[:2], fmt.Sprintf("%s_%d.jpg", hash, SnapSize(size)))
}

// SnapSize returns the smallest generated size >= want (largest if none).
func SnapSize(want int) int {
	for _, s := range Sizes {
		if want <= s {
			return s
		}
	}
	return Sizes[len(Sizes)-1]
}

// Put generates all sizes for img unless they already exist, and returns
// the hash. Images smaller than a target size are not upscaled.
func (c *Cache) Put(img []byte) (string, error) {
	hash := Hash(img)
	if c.has(hash) {
		return hash, nil
	}
	src, _, err := image.Decode(bytes.NewReader(img))
	if err != nil {
		return "", fmt.Errorf("decode cover: %w", err)
	}
	if err := os.MkdirAll(filepath.Join(c.dir, hash[:2]), 0o755); err != nil {
		return "", err
	}
	// Largest first so each step downsizes from the previous result: much
	// cheaper than resizing a 3000px source three times.
	cur := src
	for _, size := range slices.Backward(Sizes) {
		cur = resize(cur, size)
		if err := writeJPEG(c.Path(hash, size), cur); err != nil {
			return "", err
		}
	}
	return hash, nil
}

func (c *Cache) has(hash string) bool {
	for _, s := range Sizes {
		if _, err := os.Stat(c.Path(hash, s)); err != nil {
			return false
		}
	}
	return true
}

func resize(src image.Image, box int) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	if w <= box && h <= box {
		return src
	}
	if w >= h {
		h = max(1, h*box/w)
		w = box
	} else {
		w = max(1, w*box/h)
		h = box
	}
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	draw.CatmullRom.Scale(dst, dst.Bounds(), src, b, draw.Src, nil)
	return dst
}

func writeJPEG(path string, img image.Image) error {
	tmp := path + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	if err := jpeg.Encode(f, img, &jpeg.Options{Quality: 85}); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, path)
}
