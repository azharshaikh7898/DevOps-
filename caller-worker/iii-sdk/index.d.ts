export interface IIIWorker {
  registerFunction(
    function_id: string,
    fn: (payload: any) => Promise<any> | any
  ): void;
  registerTrigger(trigger: any): void;
  trigger(options: { function_id: string; payload: any }): Promise<any>;
}

export function registerWorker(url: string): IIIWorker;
