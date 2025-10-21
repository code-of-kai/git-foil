/// Sparkle permutation family implementation
///
/// Based on the NIST LWC Sparkle specification:
/// https://csrc.nist.gov/CSRC/media/Projects/Lightweight-Cryptography/documents/finalist-round/updated-spec-doc/sparkle-spec-final.pdf
///
/// Sparkle is an ARX (Add-Rotate-XOR) permutation family.
/// - Sparkle-256: 8 x 32-bit words (256 bits)
/// - Sparkle-384: 12 x 32-bit words (384 bits)
/// - Sparkle-512: 16 x 32-bit words (512 bits)

/// ARZ constants for Sparkle permutation
const RCON: [u32; 16] = [
    0xB7E15162, 0xBF715880, 0x38B4DA56, 0x324E7738,
    0xBB1185EB, 0x4F7C7B57, 0xCFBFA1C8, 0xC2B3293D,
    0xB7E15162, 0xBF715880, 0x38B4DA56, 0x324E7738,
    0xBB1185EB, 0x4F7C7B57, 0xCFBFA1C8, 0xC2B3293D,
];

/// Alzette transformation - the core 64-bit ARX-box
/// Takes two 32-bit words and a round constant, returns transformed pair
#[inline(always)]
fn alzette(x: u32, y: u32, c: u32) -> (u32, u32) {
    let mut x = x;
    let mut y = y;

    // Round 1
    x = x.wrapping_add(y.rotate_right(31));
    y = y ^ x.rotate_right(24);
    x = x ^ c;

    // Round 2
    x = x.wrapping_add(y.rotate_right(17));
    y = y ^ x.rotate_right(17);
    x = x ^ c;

    // Round 3
    x = x.wrapping_add(y);
    y = y ^ x.rotate_right(31);
    x = x ^ c;

    // Round 4
    x = x.wrapping_add(y.rotate_right(24));
    y = y ^ x.rotate_right(16);
    x = x ^ c;

    (x, y)
}

/// ELL function: rotate by 16 and XOR with left-shifted version
#[inline(always)]
fn ell(x: u32) -> u32 {
    (x ^ (x << 16)).rotate_right(16)
}

/// Linear layer for Sparkle permutation (generic over state size)
/// Follows the reference C implementation exactly
#[inline(always)]
fn linear_layer(state: &mut [u32]) {
    let nb = state.len() / 2; // Number of branches
    let b = nb / 2; // Half-branches (for Sparkle-512: 8 branches, b=4)

    // Split state into x and y arrays (interleaved representation)
    let mut x = vec![0u32; nb];
    let mut y = vec![0u32; nb];
    for i in 0..nb {
        x[i] = state[2 * i];
        y[i] = state[2 * i + 1];
    }

    // Feistel function (adding to y part)
    let mut tmp = 0;
    for i in 0..b {
        tmp ^= x[i];
    }
    tmp = ell(tmp);
    for i in 0..b {
        y[i + b] ^= tmp ^ y[i];
    }

    // Feistel function (adding to x part)
    tmp = 0;
    for i in 0..b {
        tmp ^= y[i];
    }
    tmp = ell(tmp);
    for i in 0..b {
        x[i + b] ^= tmp ^ x[i];
    }

    // Branch swap with 1-branch left-rotation of right side
    // x part
    let tmp_x = x[0];
    for i in 0..b - 1 {
        x[i] = x[i + b + 1];
        x[i + b + 1] = x[i + 1];
    }
    x[b - 1] = x[b];
    x[b] = tmp_x;

    // y part
    let tmp_y = y[0];
    for i in 0..b - 1 {
        y[i] = y[i + b + 1];
        y[i + b + 1] = y[i + 1];
    }
    y[b - 1] = y[b];
    y[b] = tmp_y;

    // Reconstruct interleaved state
    for i in 0..nb {
        state[2 * i] = x[i];
        state[2 * i + 1] = y[i];
    }
}

/// Generic Sparkle permutation for any size
/// Applies `steps` rounds of the Sparkle permutation
/// Follows reference C implementation exactly
#[inline]
fn sparkle_generic(state: &mut [u32], steps: usize) {
    let nb = state.len() / 2; // Number of branches

    for step in 0..steps {
        // Add step counter to y[0] and y[1] (indices 1 and 3 in interleaved)
        state[1] ^= RCON[step % 8]; // y[0]
        state[3] ^= step as u32;     // y[1]

        // Apply Alzette (ARXBOX) to all branches
        for i in 0..nb {
            let (x, y) = alzette(state[2 * i], state[2 * i + 1], RCON[i % 8]);
            state[2 * i] = x;
            state[2 * i + 1] = y;
        }

        // Apply linear layer
        linear_layer(state);
    }
}

/// Sparkle-256 permutation (8 x 32-bit words)
pub fn sparkle_256(state: &mut [u32; 8], steps: usize) {
    sparkle_generic(state, steps);
}

/// Sparkle-384 permutation (12 x 32-bit words)
pub fn sparkle_384(state: &mut [u32; 12], steps: usize) {
    sparkle_generic(state, steps);
}

/// Sparkle-512 permutation (16 x 32-bit words)
pub fn sparkle_512(state: &mut [u32; 16], steps: usize) {
    sparkle_generic(state, steps);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_alzette_deterministic() {
        let (x1, y1) = alzette(0x12345678, 0x9ABCDEF0, 0xCAFEBABE);
        let (x2, y2) = alzette(0x12345678, 0x9ABCDEF0, 0xCAFEBABE);
        // Same inputs should produce same outputs
        assert_eq!(x1, x2);
        assert_eq!(y1, y2);
    }

    #[test]
    fn test_sparkle_256_deterministic() {
        let mut state1 = [1u32, 2, 3, 4, 5, 6, 7, 8];
        let mut state2 = [1u32, 2, 3, 4, 5, 6, 7, 8];

        sparkle_256(&mut state1, 7);
        sparkle_256(&mut state2, 7);

        assert_eq!(state1, state2);
    }

    #[test]
    fn test_sparkle_256_changes_state() {
        let original = [1u32, 2, 3, 4, 5, 6, 7, 8];
        let mut state = original;

        sparkle_256(&mut state, 7);

        assert_ne!(state, original);
    }
}
