#!/usr/bin/env python3
"""
Model Preparation Script for IMP (Inference Machine Pipeline)

Converts Hugging Face model files to ISP binary format for FPGA loading.

Usage:
    python3 scripts/prepare_model.py --model model.safetensors --output model.isp --type qwen9b
    python3 scripts/prepare_model.py --model feeder_0.5b.bin --output feeder.isp --type feeder
"""

import argparse
import struct
import json
import hashlib

MODEL_MAGIC = 0x49535000  # "ISP\0"
VERSION = 1

def calculate_checksum(data: bytes) -> int:
    """Simple checksum - sum of all 32-bit words mod 2^32"""
    checksum = 0
    for i in range(0, len(data) & ~3, 4):
        checksum = (checksum + struct.unpack('<I', data[i:i+4])[0]) & 0xFFFFFFFF
    return checksum

def parse_safetensors_header(filepath: str) -> dict:
    """Read safetensors header to get model shape"""
    with open(filepath, 'rb') as f:
        header_size = struct.unpack('<Q', f.read(8))[0]
        header = json.loads(f.read(header_size))
    return header

def create_isp_header(model_type: str, embedding_size: int, layer_count: int, data_size: int) -> bytes:
    """Create ISP binary header"""
    header = struct.pack('<IIIIIIIQ',
        MODEL_MAGIC,           # magic
        VERSION,              # version
        0 if model_type == 'qwen9b' else 1,  # model_type
        layer_count,          # layer_count
        embedding_size,       # embedding_size
        1,                   # quantized (1 = ternary 1.58-bit)
        data_size,            # size_bytes
        0                     # checksum (filled later)
    )
    return header

def prepare_qwen9b_model(input_file: str, output_file: str):
    """Convert Ternary-Bonsai-8B model to ISP format"""
    print(f"Preparing Qwen 9B model: {input_file}")
    
    # Parse header to determine structure
    header = parse_safetensors_header(input_file)
    print(f"Model tensors: {list(header.keys())}")
    
    # For now, create a simple passthrough conversion
    # In production, this would properly parse and quantize the weights
    with open(input_file, 'rb') as f_in:
        data = f_in.read()
    
    # Calculate embedding size and layer count from header
    # This is model-specific - adjust based on actual structure
    embedding_size = 4096  # Qwen 9B hidden size
    layer_count = len([k for k in header.keys() if 'weight' in k])
    
    # Create ISP file
    isp_header = create_isp_header('qwen9b', embedding_size, layer_count, len(data))
    
    with open(output_file, 'wb') as f_out:
        f_out.write(isp_header)
        f_out.write(data)
    
    # Update checksum
    with open(output_file, 'r+b') as f:
        f.seek(24)  # Checksum offset
        checksum = calculate_checksum(data)
        f.write(struct.pack('<I', checksum))
    
    print(f"Created: {output_file} ({len(data) / 1024 / 1024:.1f} MB)")

def prepare_feeder_model(input_file: str, output_file: str):
    """Prepare feeder model (already in bin format)"""
    print(f"Preparing Feeder 0.5B model: {input_file}")
    
    with open(input_file, 'rb') as f_in:
        data = f_in.read()
    
    embedding_size = 2048  # Feeder embedding size
    layer_count = 1
    
    isp_header = create_isp_header('feeder', embedding_size, layer_count, len(data))
    
    with open(output_file, 'wb') as f_out:
        f_out.write(isp_header)
        f_out.write(data)
    
    # Update checksum
    with open(output_file, 'r+b') as f:
        f.seek(24)
        checksum = calculate_checksum(data)
        f.write(struct.pack('<I', checksum))
    
    print(f"Created: {output_file} ({len(data) / 1024 / 1024:.1f} MB)")

def main():
    parser = argparse.ArgumentParser(description='Prepare models for IMP FPGA loading')
    parser.add_argument('--model', required=True, help='Input model file')
    parser.add_argument('--output', required=True, help='Output ISP file')
    parser.add_argument('--type', choices=['qwen9b', 'feeder', 'bitcpm'], required=True,
                        help='Model type')
    args = parser.parse_args()
    
    if args.type == 'qwen9b':
        prepare_qwen9b_model(args.model, args.output)
    elif args.type in ['feeder', 'bitcpm']:
        prepare_feeder_model(args.model, args.output)

if __name__ == '__main__':
    main()