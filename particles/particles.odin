package particles

import fmt "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"

Vector2 :: [2]f32
Vec2 :: [2]f32
Color :: [4]u8

/*
    Todo:
     * Easing curves -- Maybe add ParticleSystem struct that can have information of which curves should be used for
     which values, and the method to add the particles can take in a system and a slice of the array.
*/

particles: #soa[dynamic]Particle

Particle :: struct {
	position_start:   Vector2,
	position_end:     Vector2,
	position_current: Vector2,
	lifetime_current: f32,
	lifetime_max:     f32,
	color_start:      Color,
	color_end:        Color,
}

ParticleSystem :: struct {
	ease: Easing,
}

Easing :: enum {
	Linear,
	In_Sine,
	Out_Sine,
	In_Out_Sine,
	In_Quad,
	Out_Quad,
	In_Out_Quad,
	In_Cubic,
	Out_Cubic,
	In_Out_Cubic,
	In_Quart,
	Out_Quart,
	In_Out_Quart,
	In_Quint,
	Out_Quint,
	In_Out_Quint,
	In_Expo,
	Out_Expo,
	In_Out_Expo,
	In_Circ,
	Out_Circ,
	In_Out_Circ,
	In_Back,
	Out_Back,
	In_Out_Back,
	In_Elastic,
	Out_Elastic,
	In_Out_Elastic,
	In_Bounce,
	Out_Bounce,
	In_Out_Bounce,
}

draw_proc: proc(center: Vec2, radius: f32, color: Color, segments := 16)

init :: proc(draw: proc(center: Vec2, radius: f32, color: Color, segments := 16)) {
	draw_proc = draw
	particles = make(#soa[dynamic]Particle, 0, 100)
}

dispose :: proc() {
	delete(particles)
}

update :: proc(deltaTime: f32) {
	/*
	particleCount := len(particles)

	for i := particleCount - 1; i >= 0; i -= 1 {
		p := &particles[i]

		// Update lifetime
		p.lifetime_current += deltaTime
		if p.lifetime_current >= p.lifetime_max {
			// Delete
			unordered_remove_soa(&particles, i)
			continue
		}

		normalized_lifetime: f32 = p.lifetime_current / p.lifetime_max

		// Update position
		t_eased := ease(normalized_lifetime, .In_Out_Quint)
		//x := math.lerp(p.position_start.x, p.position_end.x, t_eased)
		// y := math.lerp(p.position_start.y, p.position_end.y, t_eased)
		p.position_current = linalg.lerp(p.position_start, p.position_end, t_eased)

		if i == 1 {
			fmt.println(p.position_current)
		}

		// Update color
		currentColor: Color = lerp_color(p.color_start, p.color_end, t_eased)

		// Draw particle
		draw_proc(p.position_current, 3, currentColor)
	}*/
}

ease :: proc(life_time: f32, ease: Easing) -> f32 {
	#partial switch (ease) {
	case .Linear:
		return life_time
	case .In_Sine:
		return 1 - math.cos((life_time * math.PI) / 2)
	case .In_Out_Quint:
		{
			if (life_time < 0.5) {
				return 16 * life_time * life_time * life_time * life_time * life_time
			} else {
				return 1 - math.pow(-2 * life_time + 2, 5) / 2
			}
		}
	case .Out_Bounce:
		{
			n1 :: 7.5625
			d1 :: 2.75

			if life_time < 1.0 / d1 {
				return n1 * life_time * life_time
			} else if life_time < 2.0 / d1 {
				t := life_time - (1.5 / d1)
				return n1 * t * t + 0.75
			} else if life_time < 2.5 / d1 {
				t := life_time - (2.25 / d1)
				return n1 * t * t + 0.9375
			} else {
				t := life_time - (2.625 / d1)
				return n1 * t * t + 0.984375
			}


		}
	}

	// function easeInOutQuint(x: number): number {
	//return x < 0.5 ? 16 * x * x * x * x * x : 1 - Math.pow(-2 * x + 2, 5) / 2;
	//
	//}

	return life_time
}

lerp_color :: proc(a: Color, b: Color, t: f32) -> Color {
	newR := math.lerp(f32(a.r), f32(b.r), t)
	newG := math.lerp(f32(a.g), f32(b.g), t)
	newB := math.lerp(f32(a.b), f32(b.b), t)
	newA := math.lerp(f32(a.a), f32(b.a), t)
	return {u8(newR), u8(newG), u8(newB), u8(newA)}
}

spawn_particle_ring :: proc(startPos: Vector2) {
	center := startPos
	count := 10
	//speed  : f32 = 170.0 // Pixels per second

	for i in 0 ..< count {
		// Calculate the angle for this specific particle (in radians)
		angle := f32(i) * (2.0 * math.PI / f32(count))

		// Create the unit direction vector using Trig
		dir := Vector2{math.cos(angle), math.sin(angle)}

		// Initialize the new particle
		p := Particle {
			position_start   = startPos,
			position_end     = startPos + (dir * 250), // Scale direction by speed
			lifetime_current = 0.0,
			lifetime_max     = 1, /*rand.float32_range(0.5, 3)*/
			color_start      = {255, 0, 0, 255},
			color_end        = {0, 255, 255, 255},
		}

		append_soa(&particles, p)
	}
}

spawn_landing_particles :: proc(bobr_position: Vector2) {
	angles := generate_angles(150, 30, 6)

	for i in 0 ..< len(angles) {

		p := Particle {
			position_start   = bobr_position,
			position_end     = bobr_position + (angles[i] * 250),
			lifetime_current = 0.0,
			lifetime_max     = rand.float32_range(0.33, 0.75),
			color_start      = {255, 0, 0, 255},
			color_end        = {0, 255, 255, 255},
		}

		append_soa(&particles, p)
	}
}

generate_angles :: proc(start_angle, end_angle: f32, count: int) -> []f32 {

	angles := make([]f32, count, context.temp_allocator)

	if count == 1 {
		angles[0] = (start_angle + end_angle) / 2.0
		return angles
	}

	step := (end_angle - start_angle) / f32(count - 1)

	for i in 0 ..< count {
		angles[i] = start_angle + (f32(i) * step)
	}

	return angles
}

