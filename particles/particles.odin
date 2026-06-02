package particles

import "core:math"
import "core:math/rand"
import "core:math/linalg"
Vector2 :: [2]f32
Vec2 :: [2]f32
Color :: [4]u8

/*
    Todo:
     * Randomness
     * Support for squares and custom sprites
     * Color gradients over time, indcluding alpha
     * Easing curves
*/

particles : #soa[dynamic]Particle

Particle :: struct {
    position : Vector2,
    velocity : Vector2,
    currentLifetime : f32,
    maxLifetime : f32,
    startColor : Color,
    endColor : Color,
}

draw_proc : proc(center: Vec2, radius: f32, color: Color, segments := 16)

init :: proc(draw : proc(center: Vec2, radius: f32, color: Color, segments := 16)) {
    draw_proc = draw
    particles = make(#soa[dynamic]Particle, 0, 100)
}

dispose :: proc() {
    delete(particles)
}

update :: proc(deltaTime : f32) {

    particleCount := len(particles)

    for i := particleCount - 1; i >= 0; i -= 1 {
        p := &particles[i]

        // Update lifetime
        p.currentLifetime += deltaTime;
        if p.currentLifetime >= p.maxLifetime
        {
            // Delete
            unordered_remove_soa(&particles, i)
            continue
        }

        // Update position
        p.position += p.velocity * deltaTime;

        // Update color
        normalizedLifetime : f32 = p.currentLifetime / p.maxLifetime
        currentColor : Color = lerp_color(p.startColor, p.endColor, normalizedLifetime)

        // Draw particle
        //raylib.DrawCircleV(p.position, 3, p.color_current)
        draw_proc(p.position, 3, currentColor)
    }
}

lerp_color :: proc(a : Color, b : Color, t : f32) -> Color {
    newR := math.lerp(f32(a.r), f32(b.r), t)
    newG := math.lerp(f32(a.g), f32(b.g), t)
    newB := math.lerp(f32(a.b), f32(b.b), t)
    newA := math.lerp(f32(a.a), f32(b.a), t)
    return { u8(newR), u8(newG), u8(newB), u8(newA) }
}

spawn_particle_ring :: proc(startPos : Vector2) {
    center := startPos
    count  := 10
    speed  : f32 = 70.0 // Pixels per second

    for i in 0..<count
    {
    // Calculate the angle for this specific particle (in radians)
        angle := f32(i) * (2.0 * math.PI / f32(count))

        // Create the unit direction vector using Trig
        dir := Vector2 { math.cos(angle), math.sin(angle) }

        // Initialize the new particle
        p := Particle {
            position        = center,
            velocity        = dir * speed, // Scale direction by speed
            currentLifetime = 0.0,
            maxLifetime     = rand.float32_range(0.5, 3),
            startColor      = {255, 0, 0, 255},
            endColor        = {0, 255, 255, 255},
        }

        append_soa(&particles, p)
    }
}