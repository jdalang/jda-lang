/* Ray tracer — 800x600, 5 spheres, shadows + diffuse + specular lighting
   Reports pixel checksum and timing. */
#include <stdio.h>
#include <math.h>
#include <time.h>

typedef struct { double x, y, z; } Vec3;
static Vec3 v3(double x, double y, double z) { return (Vec3){x, y, z}; }
static Vec3 v3add(Vec3 a, Vec3 b) { return v3(a.x+b.x, a.y+b.y, a.z+b.z); }
static Vec3 v3sub(Vec3 a, Vec3 b) { return v3(a.x-b.x, a.y-b.y, a.z-b.z); }
static Vec3 v3mul(Vec3 a, double s) { return v3(a.x*s, a.y*s, a.z*s); }
static double v3dot(Vec3 a, Vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
static Vec3 v3norm(Vec3 v) { double l=sqrt(v3dot(v,v)); return v3(v.x/l,v.y/l,v.z/l); }

typedef struct { Vec3 center; double radius; Vec3 color; double specular; } Sphere;

static Sphere spheres[5];
static int nspheres = 5;

static void init_scene(void) {
    spheres[0] = (Sphere){v3(0,-1,8), 2, v3(255,50,50), 500};
    spheres[1] = (Sphere){v3(3,0,10), 1.5, v3(50,50,255), 100};
    spheres[2] = (Sphere){v3(-3,0,10), 1.5, v3(50,255,50), 200};
    spheres[3] = (Sphere){v3(0,2,12), 1, v3(255,255,50), 1000};
    spheres[4] = (Sphere){v3(0,-5001,0), 5000, v3(200,200,200), 10};
}

static double intersect(Vec3 orig, Vec3 dir, Sphere *s) {
    Vec3 oc = v3sub(orig, s->center);
    double a = v3dot(dir, dir);
    double b = 2 * v3dot(oc, dir);
    double c = v3dot(oc, oc) - s->radius * s->radius;
    double disc = b*b - 4*a*c;
    if (disc < 0) return 1e18;
    double sq = sqrt(disc);
    double t1 = (-b - sq) / (2*a);
    double t2 = (-b + sq) / (2*a);
    if (t1 > 0.001) return t1;
    if (t2 > 0.001) return t2;
    return 1e18;
}

static int clamp(int v) { return v < 0 ? 0 : v > 255 ? 255 : v; }

static Vec3 trace(Vec3 orig, Vec3 dir, int depth) {
    double closest = 1e18;
    int hit = -1;
    for (int i = 0; i < nspheres; i++) {
        double t = intersect(orig, dir, &spheres[i]);
        if (t < closest) { closest = t; hit = i; }
    }
    if (hit < 0) return v3(30, 30, 60); /* background */

    Vec3 point = v3add(orig, v3mul(dir, closest));
    Vec3 normal = v3norm(v3sub(point, spheres[hit].center));

    /* Lighting */
    Vec3 light_pos = v3(-5, 5, 0);
    Vec3 light_dir = v3norm(v3sub(light_pos, point));

    /* Shadow check */
    int in_shadow = 0;
    for (int i = 0; i < nspheres; i++) {
        if (i == hit) continue;
        if (intersect(point, light_dir, &spheres[i]) < 1e17) { in_shadow = 1; break; }
    }

    double ambient = 0.15;
    double diffuse = 0, specular = 0;
    if (!in_shadow) {
        diffuse = v3dot(normal, light_dir);
        if (diffuse < 0) diffuse = 0;
        /* Specular (Blinn-Phong) */
        Vec3 view = v3mul(dir, -1);
        Vec3 half = v3norm(v3add(light_dir, view));
        double s = v3dot(normal, half);
        if (s > 0) specular = pow(s, spheres[hit].specular);
    }
    double intensity = ambient + 0.7 * diffuse + 0.3 * specular;
    Vec3 c = spheres[hit].color;
    return v3(c.x * intensity, c.y * intensity, c.z * intensity);
}

int main(void) {
    init_scene();
    int W = 800, H = 600;
    Vec3 camera = v3(0, 0, 0);
    long checksum = 0;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            double px = (x - W/2.0) / (double)W;
            double py = -(y - H/2.0) / (double)W;
            Vec3 dir = v3norm(v3(px, py, 1));
            Vec3 col = trace(camera, dir, 0);
            int r = clamp((int)col.x), g = clamp((int)col.y), b = clamp((int)col.z);
            checksum += r * 17 + g * 31 + b * 53;
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    long ms = (t1.tv_sec - t0.tv_sec)*1000 + (t1.tv_nsec - t0.tv_nsec)/1000000;
    printf("checksum: %ld\n", checksum);
    printf("time: %ld ms\n", ms);
    return 0;
}
