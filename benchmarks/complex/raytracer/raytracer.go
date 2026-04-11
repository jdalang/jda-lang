package main

import (
	"fmt"
	"math"
	"time"
)

type Vec3 struct{ x, y, z float64 }

func v3(x, y, z float64) Vec3       { return Vec3{x, y, z} }
func v3add(a, b Vec3) Vec3           { return Vec3{a.x + b.x, a.y + b.y, a.z + b.z} }
func v3sub(a, b Vec3) Vec3           { return Vec3{a.x - b.x, a.y - b.y, a.z - b.z} }
func v3mul(a Vec3, s float64) Vec3   { return Vec3{a.x * s, a.y * s, a.z * s} }
func v3dot(a, b Vec3) float64        { return a.x*b.x + a.y*b.y + a.z*b.z }
func v3norm(v Vec3) Vec3 {
	l := math.Sqrt(v3dot(v, v))
	return Vec3{v.x / l, v.y / l, v.z / l}
}

type Sphere struct {
	center   Vec3
	radius   float64
	color    Vec3
	specular float64
}

func intersect(orig, dir Vec3, s *Sphere) float64 {
	oc := v3sub(orig, s.center)
	a := v3dot(dir, dir)
	b := 2 * v3dot(oc, dir)
	c := v3dot(oc, oc) - s.radius*s.radius
	disc := b*b - 4*a*c
	if disc < 0 {
		return 1e18
	}
	sq := math.Sqrt(disc)
	t1 := (-b - sq) / (2 * a)
	t2 := (-b + sq) / (2 * a)
	if t1 > 0.001 {
		return t1
	}
	if t2 > 0.001 {
		return t2
	}
	return 1e18
}

func clamp(v int) int {
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return v
}

var spheres []Sphere

func trace(orig, dir Vec3) Vec3 {
	closest := 1e18
	hit := -1
	for i := range spheres {
		t := intersect(orig, dir, &spheres[i])
		if t < closest {
			closest = t
			hit = i
		}
	}
	if hit < 0 {
		return v3(30, 30, 60)
	}
	point := v3add(orig, v3mul(dir, closest))
	normal := v3norm(v3sub(point, spheres[hit].center))
	lightPos := v3(-5, 5, 0)
	lightDir := v3norm(v3sub(lightPos, point))

	inShadow := false
	for i := range spheres {
		if i == hit {
			continue
		}
		if intersect(point, lightDir, &spheres[i]) < 1e17 {
			inShadow = true
			break
		}
	}

	ambient := 0.15
	diffuse := 0.0
	specular := 0.0
	if !inShadow {
		diffuse = v3dot(normal, lightDir)
		if diffuse < 0 {
			diffuse = 0
		}
		view := v3mul(dir, -1)
		half := v3norm(v3add(lightDir, view))
		s := v3dot(normal, half)
		if s > 0 {
			specular = math.Pow(s, spheres[hit].specular)
		}
	}
	intensity := ambient + 0.7*diffuse + 0.3*specular
	c := spheres[hit].color
	return v3(c.x*intensity, c.y*intensity, c.z*intensity)
}

func main() {
	spheres = []Sphere{
		{v3(0, -1, 8), 2, v3(255, 50, 50), 500},
		{v3(3, 0, 10), 1.5, v3(50, 50, 255), 100},
		{v3(-3, 0, 10), 1.5, v3(50, 255, 50), 200},
		{v3(0, 2, 12), 1, v3(255, 255, 50), 1000},
		{v3(0, -5001, 0), 5000, v3(200, 200, 200), 10},
	}
	W, H := 800, 600
	camera := v3(0, 0, 0)
	var checksum int64
	t0 := time.Now()
	for y := 0; y < H; y++ {
		for x := 0; x < W; x++ {
			px := (float64(x) - float64(W)/2.0) / float64(W)
			py := -(float64(y) - float64(H)/2.0) / float64(W)
			dir := v3norm(v3(px, py, 1))
			col := trace(camera, dir)
			r := clamp(int(col.x))
			g := clamp(int(col.y))
			b := clamp(int(col.z))
			checksum += int64(r*17 + g*31 + b*53)
		}
	}
	ms := time.Since(t0).Milliseconds()
	fmt.Printf("checksum: %d\n", checksum)
	fmt.Printf("time: %d ms\n", ms)
}
