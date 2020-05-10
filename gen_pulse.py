import pigpio

pi = pigpio.pi()
pi.set_mode(18,pigpio.OUTPUT)
while True:
    a=raw_input('freq[kHz](0.001-125000)?: ')
    if a == "quit":
        print a
        pi.hardware_PWM(18,0,0)
        pi.set_mode(18,pigpio.INPUT)
        pi.stop()
        break
    else:
        pi.hardware_PWM(18,float(a)*1000,250000)
        


