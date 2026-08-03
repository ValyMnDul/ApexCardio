#ifndef ADS1292R_REGISTERS_H
#define ADS1292R_REGISTERS_H

// Device Identification
#define ADS1292_REG_ID          0x00  // Read-only ID register (Factory ID: 0x53 / 0x73)

// Global Configuration Registers
#define ADS1292_REG_CONFIG1     0x01  // Sets sampling rate (125, 250, 500, 1000, 2000, 4000, 8000 SPS)
#define ADS1292_REG_CONFIG2     0x02  // Configures internal reference voltage (2.42V) and test signals
#define ADS1292_REG_LOFF        0x03  // Lead-Off detection control (checks if ECG electrodes fell off)

// Channel Specific Settings
#define ADS1292_REG_CH1SET      0x04  // Channel 1 Gain (1, 2, 3, 4, 6, 8, 12) & Input Multiplexer Settings
#define ADS1292_REG_CH2SET      0x05  // Channel 2 Gain (1, 2, 3, 4, 6, 8, 12) & Input Multiplexer Settings

// Right Leg Drive & Lead-Off Sensing
#define ADS1292_REG_RLD_SENS    0x06  // Right Leg Drive (RLD) signal selection & noise rejection
#define ADS1292_REG_LOFF_SENS   0x07  // Selects which channels are monitored for electrode disconnection

// Respiration & Miscellaneous Control
#define ADS1292_REG_LOFF_STAT   0x08  // Lead-Off Status register (Read-only status bits)
#define ADS1292_REG_RESP1       0x09  // Respiration Control 1 (Phase, Frequency, Internal/External Modulator)
#define ADS1292_REG_RESP2       0x0A  // Respiration Control 2 (Internal Calibration, RLD Reference Source)
#define ADS1292_REG_GPIO        0x0B  // General Purpose I/O Pin Control Register

// System Commands
#define ADS1292_CMD_WAKEUP      0x02  // Wake-up the chip from Standby mode
#define ADS1292_CMD_STANDBY     0x04  // Enter low-power Standby mode
#define ADS1292_CMD_RESET       0x06  // Reset all registers to default state
#define ADS1292_CMD_START       0x08  // Start conversion (Data sampling begins)
#define ADS1292_CMD_STOP        0x0A  // Stop conversion (Data sampling pauses)

// Data Read Commands
#define ADS1292_CMD_RDATAC      0x10  // Enable Read Data Continuous mode (Default state)
#define ADS1292_CMD_SDATAC      0x11  // Stop Read Data Continuous mode (REQUIRED before reading/writing registers)
#define ADS1292_CMD_RDATA       0x12  // Read data by command (Read a single conversion sample manually)

// Register Access Commands (Bitmask Base)
#define ADS1292_CMD_RREG        0x20  // Base opcode to Read Register  (Format: 0x20 | reg_address)
#define ADS1292_CMD_WREG        0x40  // Base opcode to Write Register (Format: 0x40 | reg_address)

#endif