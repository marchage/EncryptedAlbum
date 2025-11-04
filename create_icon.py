from PIL import Image, ImageDraw
import os

def create_gradient_image(size):
    """Create a yellow to red gradient background"""
    img = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(img)
    
    for y in range(size):
        ratio = y / size
        r = int(255 * (0.98 + 0.02 * ratio))
        g = int(220 * (1 - ratio * 0.4))
        b = int(100 * (1 - ratio))
        draw.line([(0, y), (size, y)], fill=(r, g, b))
    
    return img

def create_rounded_mask(size, radius):
    """Create a rounded rectangle mask"""
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (size-1, size-1)], radius=radius, fill=255)
    return mask

def create_icon(size):
    # Create gradient background
    gradient = create_gradient_image(size)
    
    # Create full transparent image
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Apply rounded corners to gradient
    corner_radius = int(size * 0.225)
    mask = create_rounded_mask(size, corner_radius)
    img.paste(gradient, (0, 0), mask)
    
    draw = ImageDraw.Draw(img)
    
    # Lock proportions
    lock_width = int(size * 0.35)
    lock_height = int(size * 0.30)
    lock_x = (size - lock_width) // 2
    lock_y = int(size * 0.45)
    
    # Shackle proportions
    shackle_width = int(lock_width * 0.65)
    shackle_height = int(size * 0.22)
    shackle_x = lock_x + (lock_width - shackle_width) // 2
    shackle_y = lock_y - shackle_height
    
    # Shackle thickness - UNIFORM
    shackle_thickness = max(int(size * 0.055), 3)
    
    # Draw outer shackle arc (white background)
    outer_bbox = [
        shackle_x - shackle_thickness,
        shackle_y,
        shackle_x + shackle_width + shackle_thickness,
        shackle_y + shackle_height * 2
    ]
    draw.chord(outer_bbox, start=180, end=0, fill='white')
    
    # Draw inner shackle arc (cut out to create uniform thickness)
    inner_width = shackle_width - (shackle_thickness * 2)
    if inner_width > 0:
        inner_bbox = [
            shackle_x + shackle_thickness,
            shackle_y + shackle_thickness,
            shackle_x + shackle_thickness + inner_width,
            shackle_y + shackle_height * 2 - shackle_thickness
        ]
        # Get the gradient color at this position to cut out
        sample_y = min(shackle_y + shackle_height, size - 1)
        gradient_sample = gradient.getpixel((size // 2, sample_y))
        draw.chord(inner_bbox, start=180, end=0, fill=gradient_sample)
    
    # Draw lock body with rounded corners
    body_corner_radius = int(lock_width * 0.15)
    draw.rounded_rectangle(
        [lock_x, lock_y, lock_x + lock_width, lock_y + lock_height],
        radius=body_corner_radius,
        fill='white'
    )
    
    # Draw keyhole
    keyhole_radius = int(lock_width * 0.12)
    keyhole_center_x = lock_x + lock_width // 2
    keyhole_center_y = lock_y + int(lock_height * 0.35)
    
    # Keyhole circle (dark red/maroon)
    draw.ellipse(
        [keyhole_center_x - keyhole_radius,
         keyhole_center_y - keyhole_radius,
         keyhole_center_x + keyhole_radius,
         keyhole_center_y + keyhole_radius],
        fill='#8B0000'
    )
    
    # Keyhole slot
    slot_width = int(keyhole_radius * 0.5)
    slot_height = int(lock_height * 0.25)
    draw.rounded_rectangle(
        [keyhole_center_x - slot_width,
         keyhole_center_y,
         keyhole_center_x + slot_width,
         keyhole_center_y + slot_height],
        radius=slot_width,
        fill='#8B0000'
    )
    
    return img

# Create all required sizes
sizes = [16, 32, 64, 128, 256, 512, 1024]
output_dir = 'SecretVault/Assets.xcassets/AppIcon.appiconset'

for size in sizes:
    img = create_icon(size)
    filename = f'icon_{size}x{size}.png'
    filepath = os.path.join(output_dir, filename)
    img.save(filepath, 'PNG')
    print(f'✓ Created {filename}')

print('✅ All icons created with uniform thickness shackle!')
