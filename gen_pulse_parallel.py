import pigpio,sys
###########################################################
#  use free user GPIO pins for 12-bit parallel PWM output
#   bit 0: 12 GPIO18
#   bit 1: 16 GPIO23
#   bit 2: 18 GPIO24
#   bit 3: 22 GPIO25
#   bit 4: 24 GPIO8
#   bit 5: 26 GPIO7
#   bit 6: 32 GPIO12
#   bit 7: 36 GPIO16  
#   bit 8: 38 GPIO20  
#   bit 9: 40 GPIO21
#   bit 10: 37 GPIO26
#   bit 11: 35 GPIO19
#
#
#   In the default, the sampling rate of the pigpiod is 5 usec and the maximum frequency would be 8000 Hz.
#   You can change this setting by re-configuration of the pigpiod by,
#   >sudo killall pigpiod
#   >sudo pigpiod -s [1,2,4,5,8,10]
#   For example, if you set the sampling rate to 1, you can select the PWM frequency from following values,
# 40000 20000 10000 8000 5000 4000 2500 2000 1600 1250  1000   800  500  400  250  200  100   50
#   See http://abyz.me.uk/rpi/pigpio/python.html#set_PWM_frequency for detail.
############################################################
if len(sys.argv)<2:
    print "Usage:",sys.argv[0],"[PHA(0-4095)]"
    sys.exit()
    
PHA = int(sys.argv[1])
PHA_bin = format(PHA,'b').zfill(12)
print "Output 12-bit value is:",PHA,PHA_bin
gpios = [18,23,24,25,8,7,12,16,20,21,26,19]
pi = pigpio.pi()
pi.set_mode(18,pigpio.OUTPUT)
while True:
    a=raw_input('freq[Hz](1-40000)?: ')
    if a == "quit":
        print a
        for pins in gpios:
            pi.set_PWM_dutycycle(pins,0)
            pi.set_PWM_frequency(pins,0)
            pi.set_mode(pins,pigpio.INPUT)
        pi.stop()
        break
    else:
        #pi.hardware_PWM(18,float(a)*1000,250000)
        bit=11
        for pins in gpios:
            pi.set_PWM_dutycycle(pins,64*int(PHA_bin[bit]))
            freq=pi.set_PWM_frequency(pins,float(a)*int(PHA_bin[bit]))
            bit-=1
        print "PWM Frequency was set to:",freq,"[Hz]"
        


