import ok
import numpy as np
import matplotlib.pyplot as plt
import binascii
import struct

import ok
import numpy as np
import matplotlib.pyplot as plt
import binascii
import struct
import time

class EIS:
    def __init__(self):
        self.nChs = 5
        self.nADCs = 8
        self.fclk = 100e6/2
        self.dds_clk = 125_000_000
        self.nbits = 32
        self.xem = ok.FrontPanel()
        #wire ins
        self.POT_I2C_WIRE_IN = 0x00
        self.DDS_WIRE_IN = 0x01
        self.F_SAMP_CN_WIRE_IN = 0x02
        self.FCLK_FSAMP_CN_WIRE_IN = 0x03
        self.GET_IQ = 0x04
        #wire outs
        self.IQ_WIRE_OUT = 0x20
        #trigger ins
        self.GLOBAL_RST_EP_TRIG_IN = (0x40,0) # convention: (ep_addr, pin#)
        self.DDS_TRIG_IN = (0x41, 0)
        self.POT_I2C_TRIG_IN = (0x42, 0)
        self.IQ_START_TRIG_IN = (0x43, 0)
        self.IQ_STOP_TRIG_IN = (0x44, 0)
        #block pipe out
        self.PIPE_OUT = 0xA0
        
        # self.nData = int(np.ceil((self.nChs*8)/16))
        self.nData = int(np.ceil((8*8)/16))
        self.xem_status = -1
        self.impedance_dict = {}

    def freq2fcw(self, freq_arr, dds_clk_in = 125_000_000, nbits=32 ): 
        nWords = int(nbits/32)
        fcw = np.zeros((len(freq_arr), nWords), dtype=np.uint32) #each word is 16 bits for okWireIn EP_DATA[15:0]
        for i in range(len(freq_arr)):
            delta_phase = np.uint64((freq_arr[i]*(2**nbits))/dds_clk_in) #used 64 to make function generic
            for j in range(nWords):
                # LSW #Little Endian --> LSW to smaller index
                # int is equivalent to remainder after modulus 2**16 
                fcw[i,j] =  (delta_phase%(2**((j+1)*32)))/(2**(j*32))
        return fcw

    def setMSB_LSB(self, MSB, LSB, shiftBits):
        Word = (MSB << shiftBits) + LSB
        return Word

    def genAdaptiveFs(self, fi,fs):
        if (fi <= fs//4):
            if (fs//fi)%4==0:
                fs_p = (fs//fi)*fi
            else:
                fs_p = (fs//(4*fi))*4*fi
        elif (fi>fs//4) and (fi<=fs//3):
            fs_p = 3*fi
        else:
            fs_p = fs
        return fs_p

    def initializeFPGA(self, bitFile):
        self.xem_status = self.xem.OpenBySerial("")
        self.xem_status = self.xem.LoadDefaultPLLConfiguration()
        self.xem_status = self.xem.ConfigureFPGA(bitFile)
        if self.xem_status != 0:
            raise ValueError('FPGA failed to Initialize. Check initialization steps in obj.initializeFPGA()')
        print("* FPGA initialized successfully!")
        
        return self.xem_status

    def setDigiPots(self, Rout=127, Rin=70):
        self.xem_status = self.xem.SetWireInValue(self.POT_I2C_WIRE_IN, self.setMSB_LSB(Rout, Rin,8)) #(127,70, 8)) #Set Pot Values <Rout, Rin>
        self.xem_status = self.xem.UpdateWireIns()
        self.xem_status = self.xem.ActivateTriggerIn(self.POT_I2C_TRIG_IN[0], self.POT_I2C_TRIG_IN[1])
        if self.xem_status != 0:
            raise ValueError('FPGA failed to set <Rout,Rin> Pots. Check initialization steps in obj.setDigiPots()')
        return self.xem_status

    def setDDS(self, fi):
        fcw = self.freq2fcw([fi])
        self.xem_status = self.xem.SetWireInValue(self.DDS_WIRE_IN, int(fcw[0,0]))        #Send DDS_DATA[31:0]
        self.xem_status = self.xem.UpdateWireIns()
        self.xem_status = self.xem.ActivateTriggerIn(self.DDS_TRIG_IN[0], self.DDS_TRIG_IN[1])
        if self.xem_status != 0:
            raise ValueError('FPGA failed to set DDS. Check initialization steps in obj.setDDS()')
        return self.xem_status

    def setFsamp_cn(self, fs, fi):
        fs = int(self.genAdaptiveFs(fi, fs))
        fclk_samp = int(self.fclk/fs)
        fs_cn = self.freq2fcw([fs])
        # print('fs_cn: ', fs_cn[0][0])
        # print('fs_cn: ', fs*43)
        self.xem_status = self.xem.SetWireInValue(self.F_SAMP_CN_WIRE_IN, 43*fs)
        self.xem_status = self.xem.SetWireInValue(self.FCLK_FSAMP_CN_WIRE_IN, fclk_samp)
        self.xem_status = self.xem.UpdateWireIns()
        if self.xem_status != 0:
            raise ValueError('FPGA failed to set Fsamp_cn. Check initialization steps in obj.setFsamp_cn()')
        return self.xem_status
    
    def stopIQ(self):
        self.xem_status = self.xem.SetWireInValue(self.GET_IQ, 0)
        self.xem_status = self.xem.UpdateWireIns()
        if self.xem_status != 0:
            raise ValueError('FPGA failed to stop IQ. Check initialization steps in obj.stopIQ()')
        return self.xem_status

    def startIQ(self):
        self.xem_status = self.xem.SetWireInValue(self.GET_IQ, 1)
        self.xem_status = self.xem.UpdateWireIns()
        if self.xem_status != 0:
            raise ValueError('FPGA failed to start IQ. Check initialization steps in obj.startIQ()')
        return self.xem_status

    def resetFPGA(self):
        self.xem_status = self.xem.ActivateTriggerIn(self.GLOBAL_RST_EP_TRIG_IN[0], self.GLOBAL_RST_EP_TRIG_IN[1])  #Trigger Reset
        self.xem_status = self.stopIQ()
        if self.xem_status != 0:
            raise ValueError('FPGA failed to reset. Check initialization steps in obj.resetFPGA()')
        return self.xem_status

    def monitorIQ(self):
        self.xem.UpdateWireOuts()
        IQ_status = self.xem.GetWireOutValue(self.IQ_WIRE_OUT)
        if self.xem_status != 0:
            raise ValueError('FPGA failed to monitor IQ. Check initialization steps in obj.monitorIQ()')
        while(IQ_status != 1):
            self.xem.UpdateWireOuts()
            IQ_status = self.xem.GetWireOutValue(self.IQ_WIRE_OUT)
        # print('IQ_status= ', IQ_status)
        return self.xem_status

    def unpackZBytes(self, read_buf):
        int_array = struct.unpack('<' + 'i' * (len(read_buf) // 4), read_buf)
        complexZ = np.array([])
        for i in range(self.nChs):
            complexZ = np.append(complexZ, complex(int_array[2*i], -int_array[2*i+1]))
        return complexZ[0]/complexZ #return Z = Vref/(Rout*Iout)
            

    def getSingleZ_FPGA(self, Rout, Rin, fs, fi):
        self.xem_status = self.resetFPGA()
        self.xem_status = self.setDigiPots(Rout, Rin)
        self.xem_status = self.setFsamp_cn(fs, fi)
        self.xem_status = self.setDDS(fi)
        # time.sleep(0.1)
        self.xem_status = self.startIQ()
        self.xem_status = self.monitorIQ()
        # time.sleep(1)
        read_buf = bytearray(self.nData*16)
        self.xem_status = self.xem.ReadFromBlockPipeOut(self.PIPE_OUT, self.nData*16, read_buf)
        # self.xem_status = self.stopIQ()
        # time.sleep(0.1)
        if self.xem_status < 0:
            raise ValueError('FPGA failed to read bytes from Pipe. Check initialization steps in obj.getSingleZ_FPGA()')
        Z_arr = self.unpackZBytes(read_buf)
        return Z_arr

    def getSpectralZ_FPGA(self, Rout, Rin, fs, fi_arr):
        for i in range(len(fi_arr)):
            print(f'*** {i}/{len(fi_arr)} | f={fi_arr[i]} Hz')
            self.impedance_dict[i] = self.getSingleZ_FPGA(Rout, Rin, fs, fi_arr[i])
            time.sleep(1)
        print("---- Completed Impedance Acquisition ----\n")
        print("---- Find complex impedance in obj.impedance_dict ----")
        print("---- Closing FPGA ---")
        self.xem.Close()

    def vanillaTest(self, Rout, Rin, fs, fi):
        fcw = self.freq2fcw([fi])
        fs = int(self.genAdaptiveFs(fi, fs))
        fclk_samp = int(self.fclk/fs)
        read_buf = bytearray(self.nData*16)
        self.xem.SetWireInValue(0x04,0)
        self.xem.UpdateWireIns()
        self.xem.ActivateTriggerIn(self.GLOBAL_RST_EP_TRIG_IN[0], self.GLOBAL_RST_EP_TRIG_IN[1])  #Trigger Reset
        self.xem.SetWireInValue(self.DDS_WIRE_IN, int(fcw[0,0]))        #Send DDS_DATA[31:0]
        self.xem.SetWireInValue(self.POT_I2C_WIRE_IN, setMSB_LSB(90, 10,8) ) #(127,70, 8)) #Set Pot Values <Rout, Rin>
        self.xem.SetWireInValue(self.F_SAMP_CN_WIRE_IN, 43*fs)
        self.xem.SetWireInValue(self.FCLK_FSAMP_CN_WIRE_IN, fclk_samp)
        self.xem.UpdateWireIns()
        #set digital pots
        self.xem_status = self.xem.ActivateTriggerIn(self.POT_I2C_TRIG_IN[0], self.POT_I2C_TRIG_IN[1])
        #start DDS 
        self.xem_status = self.xem.ActivateTriggerIn(self.DDS_TRIG_IN[0], self.DDS_TRIG_IN[1])
        self.xem.SetWireInValue(0x04,1)
        self.xem.UpdateWireIns()
        self.xem.UpdateWireOuts()
        IQ_status = self.xem.GetWireOutValue(self.IQ_WIRE_OUT)
        while(IQ_status != 1):
            self.xem.UpdateWireOuts()
            IQ_status = self.xem.GetWireOutValue(self.IQ_WIRE_OUT)
        self.xem.ReadFromBlockPipeOut(self.PIPE_OUT, self.nData*16, read_buf)
        self.xem.Close()
        return read_buf

